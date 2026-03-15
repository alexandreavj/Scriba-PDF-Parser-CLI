//
//  TextExtractor.swift
//  Scriba PDF Parser
//
//  Created by Alexandre Jacob on 15/03/2026.
//

import PDFKit


struct TextExtractor {
    let pdfURL: URL
    
    func extractText() throws -> NSMutableAttributedString {
        if let document = PDFDocument(url: self.pdfURL) {
            let pageCount = document.pageCount
            let documentContent = NSMutableAttributedString()

            for i in 0 ..< pageCount {
                guard let page = document.page(at: i) else { continue }
                guard let pageContent = page.attributedString else { continue }
                documentContent.append(pageContent)
            }
            
            return documentContent
        } else {
            throw ExtractionError.unableToLoadPDF(message: "Could not load PDF file with path \(self.pdfURL.path).");
        }
    }
    
    
    enum ExtractionError: Error {
        case unableToLoadPDF(message: String)
    }
}
