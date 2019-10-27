//
//  SwiftyReceiptValidator+URLSession.swift
//  SwiftyReceiptValidator
//
//  Created by Dominik Ringler on 29/01/2019.
//  Copyright © 2019 Dominik. All rights reserved.
//

import Foundation

extension SwiftyReceiptValidator {
    
    func urlSessionRequest(sharedSecret: String?,
                           refreshLocalReceiptIfNeeded: Bool,
                           excludeOldTransactions: Bool,
                           handler: @escaping (Result<SRVReceiptResponse, SRVError>) -> Void) {
        receiptFetcher.fetch(requestRefreshIfNoneFound: refreshLocalReceiptIfNeeded) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let receiptURL):
                do {
                    let receiptData = try Data(contentsOf: receiptURL)
                    self.startURLSession(
                        with: receiptData,
                        sharedSecret: sharedSecret,
                        excludeOldTransactions: excludeOldTransactions,
                        handler: handler
                    )
                } catch {
                    print(error)
                    handler(.failure(.other(error)))
                }
            case .failure(let error):
                print(error)
                handler(.failure(.other(error)))
            }
        }
    }
}

// MARK: - Private

private enum ParamsKey: String {
    case data = "receipt-data"
    case excludeOldTransactions = "exclude-old-transactions"
    case password
}

private extension SwiftyReceiptValidator {
    
    func startURLSession(with receiptData: Data,
                         sharedSecret: String?,
                         excludeOldTransactions: Bool,
                         handler: @escaping (Result<SRVReceiptResponse, SRVError>) -> Void) {
        // Prepare receipt base 64 string
        let receiptBase64String = receiptData.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))
        
        // Prepare url session parameters
        var parameters: [String: Any] = [
            ParamsKey.data.rawValue: receiptBase64String,
            ParamsKey.excludeOldTransactions.rawValue: excludeOldTransactions
        ]
        
        if let sharedSecret = sharedSecret {
            parameters[ParamsKey.password.rawValue] = sharedSecret
        }
        
        // Start URL request to production server first, if status code returns test environment receipt, try sandbox.
        // This handles validation directily with apple. This is not the recommended way by apple as it is not secure.
        // It is still better than not doing any validation at all.
        sessionManager.start(with: configuration.productionURL, parameters: parameters) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                print("SwiftyReceiptValidator success (PRODUCTION)")
                if response.status == .testReceipt {
                    print("SwiftyReceiptValidator production mode with a Sandbox receipt, trying sandbox mode...")
                    self.startSandboxRequest(parameters: parameters, handler: handler)
                } else {
                    handler(.success(response))
                }
            case .failure(let error):
                print(error)
                handler(.failure(.other(error)))
            }
        }
    }
}

// MARK: - Private Methods

private extension SwiftyReceiptValidator {
    
    func startSandboxRequest(parameters: [AnyHashable: Any], handler: @escaping (Result<SRVReceiptResponse, SRVError>) -> Void) {
        sessionManager.start(with: configuration.sandboxURL, parameters: parameters) { result in
            switch result {
            case .success(let response):
                print("SwiftyReceiptValidator success (SANDBOX) with response \(response)")
                handler(.success(response))
            case .failure(let error):
                print(error)
                handler(.failure(.other(error)))
            }
        }
    }
}
