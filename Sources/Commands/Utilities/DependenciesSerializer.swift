//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import PackageModel
import PackageGraph

protocol DependenciesDumper {
    func dump(dependenciesOf: ResolvedPackage, on: OutputByteStream)
}

final class PlainTextDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func recursiveWalk(packages: [ResolvedPackage], prefix: String = "") {
            var hanger = prefix + "├── "

            for (index, package) in packages.enumerated() {
                if index == packages.count - 1 {
                    hanger = prefix + "└── "
                }

                let pkgVersion = package.manifest.version?.description ?? "unspecified"

                stream.send("\(hanger)\(package.identity.description)<\(package.manifest.packageLocation)@\(pkgVersion)>\n")

                if !package.dependencies.isEmpty {
                    let replacement = (index == packages.count - 1) ?  "    " : "│   "
                    var childPrefix = hanger
                    let startIndex = childPrefix.index(childPrefix.endIndex, offsetBy: -4)
                    childPrefix.replaceSubrange(startIndex..<childPrefix.endIndex, with: replacement)
                    recursiveWalk(packages: package.dependencies, prefix: childPrefix)
                }
            }
        }

        if !rootpkg.dependencies.isEmpty {
            stream.send(".\n")
            recursiveWalk(packages: rootpkg.dependencies)
        } else {
            stream.send("No external dependencies found\n")
        }
    }
}

final class FlatListDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func recursiveWalk(packages: [ResolvedPackage]) {
            for package in packages {
                stream.send(package.identity.description).send("\n")
                if !package.dependencies.isEmpty {
                    recursiveWalk(packages: package.dependencies)
                }
            }
        }
        if !rootpkg.dependencies.isEmpty {
            recursiveWalk(packages: rootpkg.dependencies)
        }
    }
}

final class DotDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        var nodesAlreadyPrinted: Set<String> = []
        func printNode(_ package: ResolvedPackage) {
            let url = package.manifest.packageLocation
            if nodesAlreadyPrinted.contains(url) { return }
            let pkgVersion = package.manifest.version?.description ?? "unspecified"
            stream.send(#""\#(url)" [label="\#(package.identity.description)\n\#(url)\n\#(pkgVersion)"]"#).send("\n")
            nodesAlreadyPrinted.insert(url)
        }

        struct DependencyURLs: Hashable {
            var root: String
            var dependency: String
        }
        var dependenciesAlreadyPrinted: Set<DependencyURLs> = []
        func recursiveWalk(rootpkg: ResolvedPackage) {
            printNode(rootpkg)
            for dependency in rootpkg.dependencies {
                let rootURL = rootpkg.manifest.packageLocation
                let dependencyURL = dependency.manifest.packageLocation
                let urlPair = DependencyURLs(root: rootURL, dependency: dependencyURL)
                if dependenciesAlreadyPrinted.contains(urlPair) { continue }

                printNode(dependency)
                stream.send(#""\#(rootURL)" -> "\#(dependencyURL)""#).send("\n")
                dependenciesAlreadyPrinted.insert(urlPair)

                if !dependency.dependencies.isEmpty {
                    recursiveWalk(rootpkg: dependency)
                }
            }
        }

        if !rootpkg.dependencies.isEmpty {
            stream.send(
                """
                digraph DependenciesGraph {
                node [shape = box]

                """
            )
            recursiveWalk(rootpkg: rootpkg)
            stream.send("}\n")
        } else {
            stream.send("No external dependencies found\n")
        }
    }
}

final class JSONDumper: DependenciesDumper {
    func dump(dependenciesOf rootpkg: ResolvedPackage, on stream: OutputByteStream) {
        func convert(_ package: ResolvedPackage) -> JSON {
            return .orderedDictionary([
                "identity": .string(package.identity.description),
                "name": .string(package.manifest.displayName), // TODO: remove?
                "url": .string(package.manifest.packageLocation),
                "version": .string(package.manifest.version?.description ?? "unspecified"),
                "path": .string(package.path.pathString),
                "dependencies": .array(package.dependencies.map(convert)),
            ])
        }

        stream.send("\(convert(rootpkg).toString(prettyPrint: true))\n")
    }
}
