//
//  main.swift
//  Scriba PDF Parser
//
//  Created by Alexandre Jacob on 15/03/2026.
//

import Foundation


func main() {
    print("<=== Scriba PDF Parser CLI ===>")
    
    print("PDF file path: ", terminator: "")
    guard let pdfPath = readLine(), !pdfPath.trimmingCharacters(in: .whitespaces).isEmpty else {
        print("Error while obtaining user input.")
        return
    }
    
    let pdfURL = URL(fileURLWithPath: pdfPath)
    let textExtractor: TextExtractor = TextExtractor(pdfURL: pdfURL)
    
    do {
        let text: [NSMutableAttributedString] = try textExtractor.extractText()
        let combinedText = NSMutableAttributedString()
        text.forEach { combinedText.append($0) }
        print(combinedText.string)
    } catch {
        fputs("Extraction failed: \(error)\n", stderr)
    }

}

main()
