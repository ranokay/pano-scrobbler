import Foundation

public enum MD5 {
    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    private static let table: [UInt32] = (0..<64).map {
        UInt32(abs(sin(Double($0 + 1))) * 4_294_967_296.0)
    }

    public static func hash(_ value: String) -> String {
        digest(Array(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func digest(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(message.count) * 8

        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }

        for byteIndex in 0..<8 {
            message.append(UInt8((bitLength >> UInt64(8 * byteIndex)) & 0xff))
        }

        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            let chunk = Array(message[chunkStart..<chunkStart + 64])
            var words = [UInt32](repeating: 0, count: 16)

            for index in 0..<16 {
                let offset = index * 4
                words[index] = UInt32(chunk[offset])
                    | (UInt32(chunk[offset + 1]) << 8)
                    | (UInt32(chunk[offset + 2]) << 16)
                    | (UInt32(chunk[offset + 3]) << 24)
            }

            var a = a0
            var b = b0
            var c = c0
            var d = d0

            for i in 0..<64 {
                let f: UInt32
                let g: Int

                switch i {
                case 0..<16:
                    f = (b & c) | ((~b) & d)
                    g = i
                case 16..<32:
                    f = (d & b) | ((~d) & c)
                    g = (5 * i + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | (~d))
                    g = (7 * i) % 16
                }

                let next = d
                d = c
                c = b
                b = b &+ rotateLeft(a &+ f &+ table[i] &+ words[g], by: shifts[i])
                a = next
            }

            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        var output: [UInt8] = []
        for word in [a0, b0, c0, d0] {
            output.append(UInt8(word & 0xff))
            output.append(UInt8((word >> 8) & 0xff))
            output.append(UInt8((word >> 16) & 0xff))
            output.append(UInt8((word >> 24) & 0xff))
        }
        return output
    }

    private static func rotateLeft(_ value: UInt32, by shift: UInt32) -> UInt32 {
        (value << shift) | (value >> (32 - shift))
    }
}
