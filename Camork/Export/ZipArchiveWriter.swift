import Foundation

enum ZipArchiveError: Error, Sendable, Equatable {
    case invalidEntryName
}

struct ZipArchiveEntry: Sendable {
    let path: String
    let data: Data
}

/// Minimal ZIP writer using the store method. It avoids a dependency while producing
/// regular .zip files that Files.app and macOS can open.
enum ZipArchiveWriter {
    static func write(entries: [ZipArchiveEntry], to outputURL: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var centralRecords: [(path: String, crc: UInt32, size: UInt32, offset: UInt32)] = []

        for entry in entries {
            try validate(entry.path)
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(archive.count)

            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(size)
            archive.appendUInt32LE(size)
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(entry.data)

            centralRecords.append((entry.path, crc, size, offset))
        }

        for record in centralRecords {
            let nameData = Data(record.path.utf8)
            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(record.crc)
            centralDirectory.appendUInt32LE(record.size)
            centralDirectory.appendUInt32LE(record.size)
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(record.offset)
            centralDirectory.append(nameData)
        }

        let centralOffset = UInt32(archive.count)
        let centralSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)
        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(centralRecords.count))
        archive.appendUInt16LE(UInt16(centralRecords.count))
        archive.appendUInt32LE(centralSize)
        archive.appendUInt32LE(centralOffset)
        archive.appendUInt16LE(0)

        try archive.write(to: outputURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func validate(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("\\")
        else {
            throw ZipArchiveError.invalidEntryName
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xedb88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
