import Foundation
import RazerKit

let usage = """
usage: razerdpi <command>

  list        show connected supported mice
  get         show the current DPI and the DPI saved in the mouse
  set <dpi>   set the DPI until the mouse is unplugged (the saved value is untouched)
  probe       (read-only) check which protocol header the mouse answers to
"""

func firstMouse() throws -> RazerMouse {
    guard let mouse = RazerMouse.connected().first else { throw RazerError.noDevice }
    return mouse
}

func run(_ args: [String]) throws {
    switch args.first {
    case "list":
        let mice = RazerMouse.connected()
        if mice.isEmpty { print("No supported Razer mouse connected.") }
        for m in mice {
            print("\(m.model.name)  pid=0x\(String(format: "%04X", m.model.productID))  firmware=\(m.firmware)  location=0x\(String(m.locationID, radix: 16))")
        }

    case "get":
        let mouse = try firstMouse()
        print("current: \(try mouse.getDPI(.temporary)) DPI")
        print("saved:   \(try mouse.getDPI(.saved)) DPI")

    case "set":
        guard args.count == 2, let dpi = Int(args[1]) else {
            print(usage)
            exit(2)
        }
        let mouse = try firstMouse()
        let applied = try mouse.setDPI(dpi, storage: .temporary)
        print("current: \(applied) DPI (temporary; the saved \(try mouse.getDPI(.saved)) DPI is unchanged)")

    case "probe":
        let mouse = try firstMouse()
        print("\(mouse.model.name), firmware \(mouse.firmware)")
        for (id, result) in mouse.probe() {
            switch result {
            case .success(let dpi): print("  transaction id 0x\(String(format: "%02X", id)): answered, DPI = \(dpi)")
            case .failure(let error): print("  transaction id 0x\(String(format: "%02X", id)): \(error)")
            }
        }

    default:
        print(usage)
        exit(args.isEmpty ? 0 : 2)
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
