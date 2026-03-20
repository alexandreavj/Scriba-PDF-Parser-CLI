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
    
    do {
        let text: [NSAttributedString] = try TextExtractor.extractText(from: pdfURL)
        let combinedText = NSMutableAttributedString()
        text.forEach { combinedText.append($0) }
        print(combinedText.string)
    } catch {
        fputs("Text extraction failed: \(error)\n", stderr)
    }
    
    do {
        let extractedRasters: ([ExtractedImage], URL) = try RasterExtractor.extractRasters(from: pdfURL)
        extractedRasters.0.forEach {
            print($0.name)
        }
    } catch {
        fputs("Raster extraction failed: \(error)\n", stderr)
    }

}

main()
