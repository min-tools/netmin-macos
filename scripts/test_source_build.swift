@main
struct PublicBuildTests {
    static func main() {
        precondition(NetminEdition.bundleIdentifier == "tools.min.netmin")
        precondition(NetminEdition.localProAccess == nil)
        precondition(NetminEdition.localAccessStatus == nil)
        print("Public source build keeps normal access rules")
    }
}
