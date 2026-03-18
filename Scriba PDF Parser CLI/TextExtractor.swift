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
/// let extractor = TextExtractor(pdfURL: url)
/// let pages = try extractor.extractText()
/// let combined = pages.reduce(into: NSMutableAttributedString()) { $0.append($1) }
/// print(combined.string)
/// ```
///
/// - Note: This type performs synchronous I/O when loading the PDF. Call it off
///   the main thread if you expect large files.
struct TextExtractor {
    
    /// The file URL of the PDF to parse.
    let pdfURL: URL
    
    
    /// Extracts attributed text for each page of the PDF.
    ///
    /// The resulting array contains one `NSAttributedString` per page,
    /// in order from the first page to the last. Pages that fail to load or parse are skipped
    /// with a console message; successfully parsed pages are returned.
    ///
    /// - Returns: An array of per-page attributed strings.
    /// - Throws: ``TextExtractor/ExtractionError``. Specifically,
    ///   ``TextExtractor/ExtractionError/unableToLoadPDF(message:)``
    ///   if the PDF cannot be opened from `pdfURL`.
    func extractText() throws -> [NSAttributedString] {
        
        if let document = PDFDocument(url: self.pdfURL) {
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
            throw ExtractionError.unableToLoadPDF(message: "Could not load PDF file with path \(self.pdfURL.path).");
        }
    }
    
    
    /// Errors that can occur while preparing or loading the PDF for extraction.
    enum ExtractionError: Error {
        
        /// The PDF file could not be opened.
        ///
        /// - Parameter message: A human-readable description of the failure,
        ///   including the path when available.
        case unableToLoadPDF(message: String)
    }
}

