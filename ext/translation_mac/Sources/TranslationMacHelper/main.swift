import Foundation

guard let operation = Operation(arguments: Array(CommandLine.arguments.dropFirst())) else {
    finish(.crash, error: Operation.usage)
}

HelperApp.run(operation)
