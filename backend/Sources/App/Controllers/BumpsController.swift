//
//  BumpsController.swift
//  BumpUp
//
//  Created by Ondrej Rafaj on 31/08/2017.
//
//

import Foundation
import Vapor
import HTTP


enum BumpsError: Error {
    case missingToken
    case missingBundleId
    case authenticationFailed(String)
}


final class BumpsController: Controller {
    
    
    static func cors(request: Request) -> ResponseRepresentable {
        let response = Response(status: .noContent)
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        response.headers["Access-Control-Allow-Methods"] = "GET,OPTIONS"
        if let origin: String = request.headers["Origin"] {
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Expose-Headers"] = "Authorization"
        }
        var headers: [String] = []
        var isContentType: Bool = false
        for headerKey in request.headers.keys {
            if (headerKey.key.lowercased() == "content-type") {
                isContentType = true
            }
            headers.append(headerKey.key)
        }
        if !isContentType {
            headers.append("Content-Type")
        }
        headers.append("*")
        if !headers.contains("Authorization") {
            headers.append("Authorization")
        }
        response.headers["Access-Control-Allow-Headers"] = headers.joined(separator: ",")
        response.headers["Access-Control-Max-Age"] = "400"
        return response
    }
    
    static func buildNumber(request: Request, drop: Droplet) throws -> ResponseRepresentable {
        let token = try authenticate(request: request, drop: drop)
        return try output(request: request, tokenData: token.makeJSON(), plainText: String(token.build))
    }
    
    static func incrementBuildNumber(request: Request, drop: Droplet) throws -> ResponseRepresentable {
        let token = try authenticate(request: request, drop: drop)
        
        if let currentBuild = request.query?["build"]?.int, token.build < currentBuild {
            token.build = (currentBuild + 1)
        }
        else {
            token.build += 1
        }
        try token.save()
        
        return try output(request: request, tokenData: token.makeJSON(), plainText: String(token.build))
    }
    
    static func token(request: Request, drop: Droplet) throws -> ResponseRepresentable {
        guard let bundleId: String = request.query?["bundle"]?.string, bundleId.characters.count > 0 else {
            throw BumpsError.missingBundleId
        }
        
        var app = try App.find(bundleId: bundleId)
        if app == nil {
            app = App.init(bundle: bundleId, added: Date())
            try app?.save()
        }
        
        let uuid = UUID().uuidString
        let hashedToken = try drop.hash.make(uuid).makeString()
        
        let token = Token(token: hashedToken, build: 0, appId: app!.id!, added: Date())
        try token.save()
        token.token = uuid
        
        return try output(request: request, tokenData: token.makeFullJSON(), plainText: String(token.token))
    }
    
}


extension BumpsController {
    
    
    fileprivate static func output(request: Request, tokenData: JSON, plainText: String) throws -> Response {
        let response = Response(status: .created)
        if let plain = request.query?["plain"]?.bool, plain == true {
            response.body = Body(plainText)
            response.headers["Content-Type"] = "text/plain; charset=utf-8"
        }
        else {
            response.body = try Body(tokenData)
            response.headers["Content-Type"] = "application/json; charset=utf-8"
        }
        return response
    }
    
    fileprivate static func authenticate(request: Request, drop: Droplet) throws -> Token {
        guard let tokenString = request.query?["token"]?.string else {
            throw BumpsError.missingToken
        }
        let hashedToken = try drop.hash.make(tokenString).makeString()
        
        guard let bundleId = request.query?["bundle"]?.string else {
            throw BumpsError.missingBundleId
        }
        
        guard let token = try Token.find(token: hashedToken) else {
            throw BumpsError.authenticationFailed("Token")
        }
        
        guard let app: App = try token.app().get() else {
            throw BumpsError.authenticationFailed("App")
        }
        
        if app.bundle != bundleId {
            throw BumpsError.authenticationFailed("Bundle ID")
        }
        
        return token
    }

}
