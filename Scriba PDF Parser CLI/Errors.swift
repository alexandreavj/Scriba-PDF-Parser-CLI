//
//  Errors.swift
//  Scriba PDF Parser CLI
//
//  Created by Alexandre Jacob on 20/03/2026.
//


/// Errors that can occur while preparing or loading the PDF for extraction.
enum ExtractionError: Error {
    
    /// The PDF file could not be opened.
    ///
    /// - Parameter message: A human-readable description of the failure,
    ///   including the path when available.
    case unableToLoadPDF(message: String)
}
