import PackageDescription

let package = Package(
  name: "ale",
  targets: [
    Target(name: "Command"),
    Target(name: "libale", dependencies: [
        .Target(name: "Command"),
    ]),
    Target(name: "ale", dependencies: [
        .Target(name: "libale"),
        .Target(name: "Command"),
    ]),
  ],
  dependencies: [
  ]
)
