import Foundation
import zlib

enum GzipHelper {
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { return nil }

        var output = Data()
        let chunk = 16_384

        data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: input.bindMemory(to: Bytef.self).baseAddress!
            )
            stream.avail_in = uInt(data.count)

            var buffer = [UInt8](repeating: 0, count: chunk)
            repeat {
                stream.next_out = UnsafeMutablePointer<Bytef>(&buffer)
                stream.avail_out = uInt(chunk)
                let status = deflate(&stream, Z_FINISH)
                if status == Z_STREAM_ERROR { break }
                let produced = chunk - Int(stream.avail_out)
                if produced > 0 { output.append(buffer, count: produced) }
            } while stream.avail_out == 0
        }

        deflateEnd(&stream)
        return output.isEmpty ? nil : output
    }
}
