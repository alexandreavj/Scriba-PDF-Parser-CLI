//
//  TextExtractor.swift
//  Scriba PDF Parser
//
//  Created by Alexandre Jacob on 15/03/2026.
//

import PDFKit


struct TextExtractor {
    let pdfURL: URL
    
    func extractText() throws -> [NSMutableAttributedString] {
        if let document = PDFDocument(url: self.pdfURL) {
            let pageCount = document.pageCount
            var documentContent: [NSMutableAttributedString] = []

            for i in 0 ..< pageCount {
                documentContent.append(NSMutableAttributedString())
                
                guard let page = document.page(at: i) else {
                    print("Could not load page \(i+1).")
                    continue
                }
                guard let pageContent = page.attributedString else {
                    print("Could not parse text from page \(i+1).")
                    continue
                }
                documentContent[i].append(pageContent)
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
