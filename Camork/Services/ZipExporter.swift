import Foundation

actor ZipExporter {
    static let shared = ZipExporter()
    
    func export(items: [MediaItem], folderName: String) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        
        // Copy media files to temporary directory
        var filePaths: [(name: String, sourceURL: URL)] = []
        for item in items {
            let sourceURL = FileStorageManager.shared.getMediaURL(fileName: item.fileName)
            let destURL = tmpDir.appendingPathComponent(item.fileName)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                filePaths.append((name: item.fileName, sourceURL: destURL))
            }
        }
        
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(folderName).zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        
        // Create ZIP file manually (iOS doesn't have Process / NSTask)
        try await createZip(from: filePaths, to: zipURL)
        
        try? FileManager.default.removeItem(at: tmpDir)
        
        return zipURL
    }
    
    private func createZip(from files: [(name: String, sourceURL: URL)], to zipURL: URL) async throws {
        let fileManager = FileManager.default
        fileManager.createFile(atPath: zipURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: zipURL)
        defer { try? fileHandle.close() }
        
        var centralDirectoryData = Data()
        var offset: UInt32 = 0
        
        for file in files {
            let fileData = try Data(contentsOf: file.sourceURL)
            let fileNameData = file.name.data(using: .utf8)!
            
            // Local file header
            var localHeader = Data()
            localHeader.append(contentsOf: localFileHeaderSignature)       // signature
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(20)) { Data($0) }) // version needed
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // general purpose bit flag
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // compression method (0 = stored)
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // last mod file time
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // last mod file date
            let crc32 = fileData.crc32()
            localHeader.append(contentsOf: withUnsafeBytes(of: crc32) { Data($0) }) // crc-32
            let compressedSize = UInt32(fileData.count)
            let uncompressedSize = UInt32(fileData.count)
            localHeader.append(contentsOf: withUnsafeBytes(of: compressedSize) { Data($0) })  // compressed size
            localHeader.append(contentsOf: withUnsafeBytes(of: uncompressedSize) { Data($0) }) // uncompressed size
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count)) { Data($0) }) // file name length
            localHeader.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // extra field length
            localHeader.append(fileNameData)
            localHeader.append(fileData)
            
            // Build central directory entry
            var centralEntry = Data()
            centralEntry.append(contentsOf: centralFileHeaderSignature)    // signature
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(20)) { Data($0) }) // version made by
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(20)) { Data($0) }) // version needed
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // general purpose bit flag
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // compression method
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // last mod file time
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })  // last mod file date
            centralEntry.append(contentsOf: withUnsafeBytes(of: crc32) { Data($0) })
            centralEntry.append(contentsOf: withUnsafeBytes(of: compressedSize) { Data($0) })
            centralEntry.append(contentsOf: withUnsafeBytes(of: uncompressedSize) { Data($0) })
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count)) { Data($0) })
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // extra field length
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // file comment length
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // disk number start
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // internal file attributes
            centralEntry.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) }) // external file attributes
            centralEntry.append(contentsOf: withUnsafeBytes(of: offset) { Data($0) })     // relative offset of local header
            centralEntry.append(fileNameData)
            
            centralDirectoryData.append(centralEntry)
            
            try fileHandle.write(contentsOf: localHeader)
            offset += UInt32(localHeader.count)
        }
        
        let centralDirOffset = offset
        
        try fileHandle.write(contentsOf: centralDirectoryData)
        
        // End of central directory record
        var eocd = Data()
        eocd.append(contentsOf: endOfCentralDirSignature)
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // disk number
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // disk with central dir
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(files.count)) { Data($0) }) // entries on this disk
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(files.count)) { Data($0) }) // total entries
        eocd.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectoryData.count)) { Data($0) }) // central dir size
        eocd.append(contentsOf: withUnsafeBytes(of: centralDirOffset) { Data($0) }) // central dir offset
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) }) // comment length
        
        try fileHandle.write(contentsOf: eocd)
    }
    
    // MARK: - ZIP constants
    
    private var localFileHeaderSignature: [UInt8] { [0x50, 0x4B, 0x03, 0x04] }
    private var centralFileHeaderSignature: [UInt8] { [0x50, 0x4B, 0x01, 0x02] }
    private var endOfCentralDirSignature: [UInt8] { [0x50, 0x4B, 0x05, 0x06] }
}

// MARK: - CRC32 extension

private extension Data {
    func crc32() -> UInt32 {
        return withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            zlibCRC32(bytes.bindMemory(to: UInt8.self).baseAddress, UInt32(count))
        }
    }
}

/// CRC-32 using zlib's crc32 function
private func zlibCRC32(_ buf: UnsafePointer<UInt8>?, _ len: UInt32) -> UInt32 {
    var crc: UInt32 = 0
    guard let buf = buf else { return crc }
    
    // CRC-32 lookup table
    var table: [UInt32] = Array(repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 {
            if c & 1 != 0 {
                c = 0xEDB88320 ^ (c >> 1)
            } else {
                c = c >> 1
            }
        }
        table[i] = c
    }
    
    crc = 0xFFFFFFFF
    for i in 0..<Int(len) {
        let index = Int((crc ^ UInt32(buf[i])) & 0xFF)
        crc = (crc >> 8) ^ table[index]
    }
    return crc ^ 0xFFFFFFFF
}
