import Foundation

/// RAR 5 store-method writer, implemented from RARLAB's published container specification.
/// Files are archived without compression; no proprietary compressor is required.
enum RARStore {
  static let table: [UInt32] = (0..<256).map { index in
    var c = UInt32(index)
    for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0xedb8_8320 : c >> 1 }
    return c
  }
  static func crc(_ data: Data, seed: UInt32 = 0xffff_ffff) -> UInt32 {
    var c = seed
    for b in data { c = table[Int((c ^ UInt32(b)) & 255)] ^ (c >> 8) }
    return c
  }
  static func uint(_ value: UInt32) -> Data {
    var n = value.littleEndian
    return withUnsafeBytes(of: &n) { Data($0) }
  }
  static func vint(_ value: UInt64) -> Data {
    var n = value
    var result = Data()
    repeat {
      var b = UInt8(n & 127)
      n >>= 7
      if n > 0 { b |= 128 }
      result.append(b)
    } while n > 0
    return result
  }
  static func header(_ body: Data) -> Data {
    let payload = vint(UInt64(body.count)) + body
    return uint(crc(payload) ^ 0xffff_ffff) + payload
  }
  static func write(_ urls: [URL], to dest: URL, engine: Engine) throws {
    let fm = FileManager.default
    fm.createFile(atPath: dest.path, contents: nil)
    let out = try FileHandle(forWritingTo: dest)
    defer { try? out.close() }
    try out.write(contentsOf: Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]))
    try out.write(contentsOf: header(Data([1, 0, 0])))
    var used = Set<String>()
    func entry(_ file: URL, name: String) throws {
      try engine.token.check()
      let values = try file.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
      ])
      guard values.isSymbolicLink != true else {
        throw ClementineError("L’archivage RAR ne prend pas en charge les liens symboliques.")
      }
      let directory = values.isDirectory == true
      let size = directory ? 0 : (values.fileSize ?? 0)
      var checksum: UInt32 = 0xffff_ffff
      if !directory {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
          try engine.token.check()
          checksum = crc(chunk, seed: checksum)
        }
      }
      let bytes = Data(name.utf8)
      var body = vint(2) + vint(directory ? 0 : 2)
      if !directory { body += vint(UInt64(size)) }
      body += vint(directory ? 3 : 6) + vint(UInt64(size)) + vint(directory ? 0o40755 : 0o100644)
      body += uint(
        UInt32(clamping: Int64((values.contentModificationDate ?? Date()).timeIntervalSince1970)))
      if !directory { body += uint(checksum ^ 0xffff_ffff) }
      body += vint(0) + vint(1) + vint(UInt64(bytes.count)) + bytes
      try out.write(contentsOf: header(body))
      if directory {
        for child in try fm.contentsOfDirectory(at: file, includingPropertiesForKeys: nil).sorted(
          by: { $0.lastPathComponent < $1.lastPathComponent })
        { try entry(child, name: name + "/" + child.lastPathComponent) }
      } else {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var copied = 0
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
          try engine.token.check()
          try out.write(contentsOf: chunk)
          copied += chunk.count
        }
        guard copied == size else {
          throw ClementineError("Un fichier a changé pendant l’archivage")
        }
      }
    }
    for (i, u) in urls.enumerated() {
      var name = u.lastPathComponent
      if used.contains(name) { name = "\(i)-" + name }
      used.insert(name)
      try entry(u, name: name)
    }
    try out.write(contentsOf: header(Data([5, 0, 0])))
  }
}
