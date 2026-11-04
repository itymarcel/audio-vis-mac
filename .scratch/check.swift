import Metal
let src = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let dev = MTLCreateSystemDefaultDevice()!
do {
    let lib = try dev.makeLibrary(source: src, options: nil)
    print("OK:", lib.functionNames.sorted().joined(separator: ", "))
} catch { print("ERROR:", error) }
