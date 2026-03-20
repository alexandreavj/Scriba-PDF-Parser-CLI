//
//  TextExtractor.swift
//  Scriba PDF Parser
//
//  Created by Alexandre Jacob on 15/03/2026.
//

import PDFKit 


/// A lightweight utility for extracting attributed text from a PDF document using PDFKit.
///
/// `TextExtractor` opens a PDF from a file URL and produces an array of
/// `NSMutableAttributedString`, one per page, preserving basic attributes
/// that PDFKit exposes (such as fonts and ligatures when available).
///
/// Typical usage:
/// ```swift
/// let pages = try TextExtractor.extractText(from: url)
/// let combined = pages.reduce(into: NSMutableAttributedString()) { $0.append($1) }
/// print(combined.string)
/// ```
///
/// - Note: This type performs synchronous I/O when loading the PDF. Call it off
///   the main thread if you expect large files.
struct TextExtractor {
    
    /// Extracts attributed text for each page of the PDF.
    ///
    /// The resulting array contains one `NSAttributedString` per page,
    /// in order from the first page to the last. Pages that fail to load or parse are skipped
    /// with a console message; successfully parsed pages are returned.
    ///
    /// - Parameter pdfURL: URL for the PDF document to extract text from.
    /// - Returns: An array of per-page attributed strings.
    /// - Throws: ``TextExtractor/ExtractionError``. Specifically,
    ///   ``TextExtractor/ExtractionError/unableToLoadPDF(message:)``
    ///   if the PDF cannot be opened from `pdfURL`.
    static func extractText(from pdfURL: URL) throws -> [NSAttributedString] {
        
        if let document = PDFDocument(url: pdfURL) {
            let pageCount = document.pageCount
            var documentContent: [NSAttributedString] = []

            for i in 0 ..< pageCount {
                // Empty NSAttributedString as default for empty/failed page
                documentContent.append(NSAttributedString())
                
                // Load PDF page
                guard let page = document.page(at: i) else {
                    print("Could not load page \(i+1).")
                    continue
                }
                // Extract PDF text as an attributed string
                guard let pageContent = page.attributedString else {
                    print("Could not parse text from page \(i+1).")
                    continue
                }
                
                // Update array with text for the given page
                documentContent[i] = pageContent
            }
            
            return documentContent
        } else {
            throw ExtractionError.unableToLoadPDF(message: "Could not load PDF file with path \(pdfURL.path).");
        }
    }
    
}

