//
//  RasterExtractor.swift
//  Scriba PDF Parser CLI
//
//  Created by Alexandre Jacob on 17/03/2026.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PDFKit


/// A lightweight class representing a raster image reference in a PDF page.
///
/// This class stores metadata about an image embedded in a PDF, including the page
/// it was found on and the PDF XObject name. It does **not** store the image bytes.
class ExtractedImage {
    
    /// Creates a new image reference.
    /// - Parameters:
    ///   - pageIndex: 1-based index of the page where the image was found.
    ///   - name: The PDF XObject key/name under which the image was referenced (e.g., "Im1").
    init(pageIndex: Int, name: String) {
        self.pageIndex = pageIndex
        self.name = name
    }
    
    /// 1-based index of the page within the `CGPDFDocument` where the image was found.
    let pageIndex: Int
    
    /// The PDF XObject key (name) under which this image was referenced.
    let name: String
    
}


/// A value type representing a single raster image extracted from a PDF page.
///
/// Instances of `ExtractedImage` are produced by `extractImages(from:)` when
/// traversing a PDF's XObject dictionaries. Each instance contains the raw
/// bytes of the image stream as found in the PDF, along with the image's
/// PDF name, the page index it was found on, and the detected data format.
///
/// Use `fileExtension(for:data:)` and `saveImage(_:to:index:)` to derive a
/// suitable filename/extension and persist it to disk.
final class ExtractedImageWithData: ExtractedImage {
    
    /// Creates a new instance with raw data and format information.
    /// - Parameters:
    ///   - pageIndex: 1-based index of the page where the image was found.
    ///   - name: The PDF XObject key/name.
    ///   - data: The raw image stream data extracted from the PDF.
    ///   - format: The format hint reported by Core Graphics (e.g., `.jpegEncoded`, `.JPEG2000`, `.raw`).
    init(pageIndex: Int, name: String, data: CFData, format: CGPDFDataFormat) {
        self.data = data
        self.format = format
        super.init(pageIndex: pageIndex, name: name)
    }
    
    /// The raw image stream data as extracted from the PDF. This may already be
    /// a complete file (e.g., JPEG/PNG) or a raw/encoded stream that requires decoding.
    let data: CFData
    
    /// The format hint reported by Core Graphics for the image stream (e.g., `.jpegEncoded`, `.JPEG2000`, `.raw`).
    let format: CGPDFDataFormat
    
}


/// A lightweight accumulator used during dictionary traversal for a single page.
///
/// `ExtractionContext` is passed through `CGPDFDictionaryApplyBlock` as an opaque
/// pointer so the callback can append discovered image streams while retaining
/// knowledge of the current page index.
final class ExtractionContext {
    
    /// 1-based page index associated with this traversal.
    let pageIndex: Int
    
    /// Collected images discovered while iterating the page's XObject dictionary.
    var images: [ExtractedImageWithData] = []
    
    /// Creates a new context for the given page index.
    /// - Parameter pageIndex: The 1-based index of the page being processed.
    init(pageIndex: Int) { self.pageIndex = pageIndex }
    
}


/// A lightweight utility for extracting raster images from a PDF document using PDFKit and Core Graphics.
///
/// `RasterExtractor` scans a PDF file, page by page, traversing each page's XObject dictionary
/// to locate embedded raster images (`Subtype == "Image"`). For each image found, it produces
/// an `ExtractedImageWithData` containing the page index, PDF XObject name, raw bytes, and
/// Core Graphics format hint.
///
/// Images can be optionally saved to disk. JPEG and PNG streams are written directly,
/// while other formats are decoded and re-encoded as PNG to ensure file compatibility.
///
/// Typical usage:
/// ```swift
/// let (images, outputDir) = try RasterExtractor.extractRaster(from: pdfURL, to: outputDirectory)
/// print("Extracted \(images.count) images to \(outputDir.path)")
/// ```
///
/// - Note: This type performs synchronous I/O when loading the PDF and writing files.
///   For large PDFs, run it off the main thread to avoid blocking the UI.
///
/// - Warning: Images with unknown or raw encodings may be re-encoded as PNG, which can
///   alter their original format or color representation.
struct RasterExtractor {
    
    /// Extracts all raster images from a PDF and optionally saves them to disk.
    ///
    /// The function scans every page's XObject dictionary, identifies streams with
    /// `Subtype == "Image"`, and collects their bytes. Images are saved to disk if
    /// `outputDir` is provided or defaults to the PDF's folder. JPEG/PNG streams are
    /// written directly; other formats are re-encoded as PNG.
    ///
    /// - Parameters:
    ///   - pdfURL: URL of the PDF file to extract images from.
    ///   - outputDir: Optional directory to save extracted images. Defaults to the PDF's folder.
    /// - Returns: A tuple containing:
    ///     1. Array of `ExtractedImageWithData` representing successfully extracted images.
    ///     2. The directory URL where images were saved.
    /// - Throws: `ExtractionError.unableToLoadPDF` if the PDF could not be opened.
    static func extractRasters(from pdfURL: URL, to outputDir: URL? = nil) throws -> ([ExtractedImage], URL) {
        
        if let document = PDFDocument(url: pdfURL)?.documentRef {
            
            // Extract raster images from document
            var extractedRasters = extractImages(from: document)
            
            // Check if outputDir exists
            let outputDir = outputDir ?? pdfURL.deletingLastPathComponent()
            
            // Save images to file
            var imageCounterInPage = 1, previousPage = 1
            var failedSaves: [Int] = []
            for (i, image) in extractedRasters.enumerated() {
                if previousPage != image.pageIndex {
                    imageCounterInPage = 1
                    previousPage = image.pageIndex
                }
                
                if !saveImage(image, to: outputDir, index: imageCounterInPage) {
                    failedSaves.append(i)
                }
            }
            
            // Remove images that were not saved to file
            for i in failedSaves.sorted(by: >) {
                extractedRasters.remove(at: i)
            }
            
            return (extractedRasters, outputDir)
            
        } else {
            throw ExtractionError.unableToLoadPDF(message: "Could not load PDF file with path \(pdfURL.path).");
        }
    }
    
    
    /// Returns the page's XObject dictionary, if available.
    ///
    /// This helper walks the PDF object hierarchy for a given page:
    /// 1. Reads the page's top-level dictionary.
    /// 2. Looks up its `Resources` dictionary.
    /// 3. Retrieves the `XObject` dictionary from within `Resources`.
    ///
    /// The XObject dictionary contains external objects referenced by the page, including raster
    /// images ("Subtype" == "Image").
    ///
    /// - Parameter page: The `CGPDFPage` whose XObject dictionary should be read.
    /// - Returns: A `CGPDFDictionaryRef` pointing to the XObject dictionary, or `nil`
    ///   if any of the intermediate dictionaries are missing.
    private static func getXObjectDictionary(from page: CGPDFPage) -> CGPDFDictionaryRef? {
        
        // Get PDF internal tree
        guard let pageDict = page.dictionary else { return nil }
        
        // Get Resources tree
        var resourcesDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resourcesDict),
              let resources = resourcesDict else { return nil }
        
        // Get XObject Dictionary
        // XObject Dictionary: where PDF embeds all external resources (including images)
        var xObjectDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjectDict) else { return nil }
        
        return xObjectDict
    }
    
    
    /// Indicates whether the given XObject stream dictionary represents an image.
    ///
    /// The check reads the `Subtype` name from the provided dictionary and compares it to the
    /// PDF value `"Image"`.
    ///
    /// - Parameter dict: The XObject's stream dictionary (from `CGPDFStreamGetDictionary`).
    /// - Returns: `true` if the dictionary's `Subtype` is `Image`; otherwise `false`.
    /// - Note: This does not validate that the stream data itself is decodable; it
    ///   only inspects the metadata.
    private static func isImageStream(_ dict: CGPDFDictionaryRef) -> Bool {
        
        var subtype: UnsafePointer<CChar>?
        
        // Look for the key "Subtype" in the XObject Inner Dictionary and write its value to `subtype`
        // If it exists and is a valid PDF Name type, `subtype` is unwrapped from UnsafePointer<CChar>?
        // to UnsafePointer<CChar>
        guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype else { return false }
        
        return String(cString: subtype) == "Image"
    }
    
    
    /// Extracts raster images from all pages in the given PDF document.
    ///
    /// This function walks each page's XObject dictionary and collects any entries whose
    /// stream dictionary indicates `Subtype == "Image"`. For each discovered image stream,
    /// it copies the raw bytes and records a format hint reported by Core Graphics
    /// (e.g., `.jpegEncoded`, `.JPEG2000`, `.raw`). The results are returned as an array of
    /// `ExtractedImage` values, each tagged with the 1-based page index and the PDF XObject name.
    ///
    /// The iteration is driven by `CGPDFDictionaryApplyBlock`, which invokes a closure once per
    /// XObject entry.
    ///
    /// - Parameter document: A `CGPDFDocument` to scan for image XObjects.
    /// - Returns: An array of `ExtractedImage` instances found across all pages, in page order.
    private static func extractImages(from document: CGPDFDocument) -> [ExtractedImageWithData] {
        
        var results: [ExtractedImageWithData] = []
        
        for pageIndex in 1...document.numberOfPages {
            
            // Load documente page and extract XObject Dictionary
            guard let page = document.page(at: pageIndex),
                  let xObjects = getXObjectDictionary(from: page) else { continue }
            
            // ExtractionContext for current page's elements
            let context = ExtractionContext(pageIndex: pageIndex)
            
            // Bridge the `context` object (ExtractionContext) to an opaque raw pointer so it
            // can be passed through the C callback API below. We use `passUnretained` here
            // because we control the lifetime of `context` in this scope and only need
            // a temporary, non-owning pointer for the duration of the dictionary walk.
            // Opaque refers to a raw, untyped pointer.
            let contextPtr = Unmanaged.passUnretained(context).toOpaque()
            
            CGPDFDictionaryApplyBlock(xObjects, { keyPtr, object, rawPtr in
                
                // Reconstruct the Swift `ExtractionContext` from the opaque pointer we
                // passed into `CGPDFDictionaryApplyBlock`.
                // - `fromOpaque` converts the raw pointer back to `Unmanaged<ExtractionContext>`
                // - `takeUnretainedValue()` matches our use of `passUnretained` above, avoiding
                //    ARC retains/releases while still giving us a safe Swift reference
                let ctx = Unmanaged<ExtractionContext>.fromOpaque(rawPtr!).takeUnretainedValue()
                let name = String(cString: keyPtr) // PDF XObject name (e.g. Im1)
                
                
                var streamRef: CGPDFStreamRef?
                
                // CGPDFObject​Get​Value(object, .stream, &stream​Ref) tries to interpret the CGPDFObject​Ref
                // named object as a PDF stream and write the result into stream​Ref
                //     - It returns true if object is indeed a stream
                //     - It returns false if it’s not
                //     - The third parameter is an output parameter that will be filled if successful
                // let stream = stream​Ref safely unwraps the optional into a non-optional stream
                // If either part fails (not a stream, or stream​Ref is nil), the guard’s else runs and
                // returns true from the closure, meaning “skip this entry and continue iterating”.
                guard CGPDFObjectGetValue(object, .stream, &streamRef), let stream = streamRef else {
                    return true
                }
                
                
                // CGPDFStream​Get​Dictionary(stream) tries to fetch the stream’s own dictionary (metadata)
                //     - If it returns nil, the stream has no dictionary to be inspected and the guard fails
                // is​Image​Stream(dict) inspects the dictionary to see if Subtype == "​Image"
                guard let dict = CGPDFStreamGetDictionary(stream), isImageStream(dict) else {
                    return true
                }
                
                
                // `format` is of type CGPDFData​Format - enum used to describe how the stream’s bytes are
                // encoded (e.g., .jpeg​Encoded, .​JPEG2000, .raw, ...)
                var format: CGPDFDataFormat = .raw
                
                // CGPDFStream​Copy​Data fills `format` with the actual format it detects from the stream’s
                // data and obtains the raw bytes of the element
                guard let data = CGPDFStreamCopyData(stream, &format) else { return true }
                
                
                // Append extracted image to `context` (ExtractionContext)
                ctx.images.append(ExtractedImageWithData(
                    pageIndex: ctx.pageIndex,
                    name: name,
                    data: data,
                    format: format
                ))
                
                // Returns true from the closure, meaning "move to the next entry"
                return true
                
            }, contextPtr)
            
            // Append images of the current page to `results`
            results.append(contentsOf: context.images)
        }
        
        return results
    }
    
    
    /// Determines a suitable file extension for extracted image data.
    ///
    /// The decision uses a combination of magic-byte sniffing (to detect PNG/JPEG reliably)
    /// and the `CGPDFDataFormat` hint provided by Core Graphics. Magic bytes take precedence
    /// because they positively identify already file-ready data. If no magic bytes are
    /// recognized, the function maps known `CGPDFDataFormat` cases to common extensions and
    /// defaults to `"bin"` for unknown/raw encodings.
    ///
    /// - Parameters:
    ///   - format: The `CGPDFDataFormat` reported by `CGPDFStreamCopyData` for the stream.
    ///   - data: The raw bytes returned by `CGPDFStreamCopyData`.
    /// - Returns: A lowercase file extension without the leading dot (e.g., `"jpg"`, `"png"`, `"jp2"`, or `"bin"`).
    private static func fileExtension(for format: CGPDFDataFormat, data: CFData) -> String {
        let bytes = CFDataGetBytePtr(data)
        // Prefer magic-byte detection when available (more authoritative than hints)
        if let bytes {
            if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF { return "jpg" }
            if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 { return "png" }
        }
        switch format {
        case .jpegEncoded:  return "jpg"   // JPEG stream
        case .JPEG2000:     return "jp2"   // JPEG 2000 stream
        default:            return "bin"   // raw/unknown (e.g., raw, CCITT, JBIG2)
        }
    }
    
    
    /// Saves an extracted image to disk, re-encoding if necessary.
    ///
    /// The function first derives a file extension from the image stream's data and format hint
    /// using `fileExtension(for:data:)`. If the extension is `jpg` or `png`, the bytes are written
    /// directly to disk as they already represent a complete file. For other/unknown encodings,
    /// the function attempts to decode the stream with ImageIO and re-encode the result as PNG.
    ///
    /// The re-encode path tries to write a PNG directly to a file URL via `CGImageDestination`.
    /// If that finalization fails, it falls back to encoding in-memory and writing the resulting data
    /// with `Data.write` to provide clearer file system error reporting. As a last resort, the raw
    /// bytes are written with minimal assumptions.
    ///
    /// - Parameters:
    ///   - extracted: The `ExtractedImage` to save (contains page index, name, bytes, and format hint).
    ///   - outputDir: The directory URL where the image should be saved.
    ///   - index: A per-page sequence index used to disambiguate multiple images with the same name.
    /// - Returns: `true` if a file was written successfully; otherwise `false`.
    ///
    /// - Note: Filenames are composed as `page<pageIndex>_<name>_<index>.<ext>`. When re-encoding, the
    ///   extension is `.png`. Errors are printed to the console for diagnostic purposes.
    private static func saveImage(_ extracted: ExtractedImageWithData, to outputDir: URL, index: Int) -> Bool {
        
        let ext = fileExtension(for: extracted.format, data: extracted.data)
        let filename = "page\(extracted.pageIndex)_\(extracted.name)_\(index).\(ext)"
        let fileURL = outputDir.appendingPathComponent(filename)
        
        // For JPEG/PNG it can be written directly — already valid files
        if ext == "jpg" || ext == "png" {
            let imageData = extracted.data as Data
            do {
                try imageData.write(to: fileURL)
                print("Saved \(filename).")
                return true
            } catch {
                print("Failed to save \(filename): \(error)")
                return false
            }
        }
        
        // Encoded formats (JP2, TIFF, etc.): let ImageIO decode then re-encode as PNG
        let pngURL = outputDir.appendingPathComponent("page\(extracted.pageIndex)_\(extracted.name)_\(index).png")
        if let source = CGImageSourceCreateWithData(extracted.data, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let md = CFDataCreateMutable(nil, 0),
           let dest = CGImageDestinationCreateWithData(md, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else {
                print("Failed to encode \(pngURL.lastPathComponent) as PNG")
                return false
            }
            do {
                try (md as Data).write(to: pngURL)
                print("Saved (re-encoded) \(pngURL.lastPathComponent)")
                return true
            } catch {
                print("Failed to write \(pngURL.lastPathComponent): \(error)")
                return false
            }
        }
        
        // Fallback: write raw bytes
        let imageData = extracted.data as Data
        do {
            try imageData.write(to: fileURL)
            print("Saved raw bytes: \(filename)")
        } catch {
            print("Failed to save \(filename): \(error)")
        }
        
        return true
    }
    
}
