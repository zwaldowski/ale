import PackageDescription

let package = Package(
  name: "ale",
  targets: [
    Target(name: "libale", dependencies: [
    ]),
    Target(name: "ale", dependencies: [
        .Target(name: "libale"),
    ]),
  ],
  dependencies: [
  ]
)
