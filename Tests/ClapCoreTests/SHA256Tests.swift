import Foundation

@MainActor
func sha256Tests() {
    test("empty input matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
    test("\"abc\" matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    test("448-bit message matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }
    test("multi-block message matches known SHA-256 vector") {
        expectEqual(clapSHA256Hex(Data(String(repeating: "a", count: 1_000_000).utf8)),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}
