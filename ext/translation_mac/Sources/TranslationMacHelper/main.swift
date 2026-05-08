import Foundation

// argv layout:
//   TranslationMacHelper translate <from> <to> <text>
//   TranslationMacHelper prepare   <from> <to>
//   TranslationMacHelper status    <from> <to>
//   TranslationMacHelper languages

let args = CommandLine.arguments

func usage() -> Never {
    FileHandle.standardError.write(Data("usage:\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper translate <from> <to> <text>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper prepare <from> <to>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper status <from> <to>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper languages\n".utf8))
    exit(5)
}

guard args.count >= 2 else { usage() }
let command = args[1]

guard #available(macOS 15.0, *) else {
    FileHandle.standardError.write(Data("requires macOS 15.0+\n".utf8))
    exit(3)
}

let app = HelperApp()

switch command {
case "translate":
    guard args.count >= 5 else { usage() }
    app.run(operation: .translate(from: args[2], to: args[3], text: args[4]))
case "prepare":
    guard args.count >= 4 else { usage() }
    app.run(operation: .prepare(from: args[2], to: args[3]))
case "status":
    guard args.count >= 4 else { usage() }
    app.run(operation: .status(from: args[2], to: args[3]))
case "languages":
    app.run(operation: .supportedLanguages)
default:
    usage()
}
