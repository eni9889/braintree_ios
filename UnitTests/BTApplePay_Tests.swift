import PassKit
import XCTest

@available(iOS 8.0, *)

class BTApplePay_Tests: XCTestCase {

    var mockClient : MockAPIClient = MockAPIClient(authorization: "development_tokenization_key")!

    override func setUp() {
        super.setUp()
        mockClient = MockAPIClient(authorization: "development_tokenization_key")!
    }

    func testTokenization_whenConfiguredOff_callsBackWithError() {
        mockClient.cannedConfigurationResponseBody = BTJSON(value: [
            "applePay" : [
                "status" : "off"
            ]
            ])
        let expectation = expectationWithDescription("Unsuccessful tokenization")

        let client = BTApplePayClient(APIClient: mockClient)
        let payment = MockPKPayment()
        client.tokenizeApplePayPayment(payment) { (tokenizedPayment, error) -> Void in
            XCTAssertEqual(error!.domain, BTApplePayErrorDomain)
            XCTAssertEqual(error!.code, BTApplePayErrorType.Unsupported.rawValue)
            expectation.fulfill()
        }
        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testTokenization_whenConfigurationIsMissingApplePayStatus_callsBackWithError() {
        mockClient.cannedConfigurationResponseBody = BTJSON(value: [:])
        let expectation = expectationWithDescription("Unsuccessful tokenization")

        let client = BTApplePayClient(APIClient: mockClient)
        let payment = MockPKPayment()
        client.tokenizeApplePayPayment(payment) { (tokenizedPayment, error) -> Void in
            XCTAssertEqual(error!.domain, BTApplePayErrorDomain)
            XCTAssertEqual(error!.code, BTApplePayErrorType.Unsupported.rawValue)
            expectation.fulfill()
        }
        waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    func testTokenization_whenAPIClientIsNil_callsBackWithError() {
        let client = BTApplePayClient(APIClient: mockClient)
        client.apiClient = nil

        let expectation = expectationWithDescription("Callback invoked")
        client.tokenizeApplePayPayment(MockPKPayment()) { (tokenizedPayment, error) -> Void in
            XCTAssertNil(tokenizedPayment)
            XCTAssertEqual(error!.domain, BTApplePayErrorDomain)
            XCTAssertEqual(error!.code, BTApplePayErrorType.Integration.rawValue)
            expectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testTokenization_whenConfigurationFetchErrorOccurs_callsBackWithError() {
        mockClient.cannedConfigurationResponseError = NSError(domain: "MyError", code: 1, userInfo: nil)
        let client = BTApplePayClient(APIClient: mockClient)
        let payment = MockPKPayment()
        let expectation = expectationWithDescription("tokenization error")

        client.tokenizeApplePayPayment(payment) { (tokenizedPayment, error) -> Void in
            XCTAssertEqual(error!.domain, "MyError")
            XCTAssertEqual(error!.code, 1)
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testTokenization_whenTokenizationErrorOccurs_callsBackWithError() {
        mockClient.cannedConfigurationResponseBody = BTJSON(value: [
            "applePay" : [
                "status" : "production"
            ]
            ])
        mockClient.cannedHTTPURLResponse = NSHTTPURLResponse(URL: NSURL(string: "any")!, statusCode: 503, HTTPVersion: nil, headerFields: nil)
        mockClient.cannedResponseError = NSError(domain: "foo", code: 100, userInfo: nil)
        let client = BTApplePayClient(APIClient: mockClient)
        let payment = MockPKPayment()
        let expectation = expectationWithDescription("tokenization failure")

        client.tokenizeApplePayPayment(payment) { (tokenizedPayment, error) -> Void in
            XCTAssertEqual(error!, self.mockClient.cannedResponseError!)
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testTokenization_whenTokenizationFailureOccurs_callsBackWithError() {
        mockClient.cannedConfigurationResponseBody = BTJSON(value: [
            "applePay" : [
                "status" : "production"
            ]
            ])
        mockClient.cannedResponseError = NSError(domain: "MyError", code: 1, userInfo: nil)
        let client = BTApplePayClient(APIClient: mockClient)
        let payment = MockPKPayment()
        let expectation = expectationWithDescription("tokenization failure")

        client.tokenizeApplePayPayment(payment) { (tokenizedPayment, error) -> Void in
            XCTAssertEqual(error!.domain, "MyError")
            XCTAssertEqual(error!.code, 1)
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(2, handler: nil)
    }

    func testTokenization_whenSuccessfulTokenizationInProduction_callsBackWithTokenizedPayment() {
        mockClient.cannedConfigurationResponseBody = BTJSON(value: [
            "applePay" : [
                "status" : "production"
            ]
        ])
        mockClient.cannedResponseBody = BTJSON(value: [
            "applePayCards": [
                [
                    "nonce" : "an-apple-pay-nonce",
                    "description": "a description",
                ]
            ]
            ])
        let expectation = expectationWithDescription("successful tokenization")

        let client = BTApplePayClient(APIClient: mockClient)
        let payment = MockPKPayment()
        client.tokenizeApplePayPayment(payment) { (tokenizedPayment, error) -> Void in
            XCTAssertNil(error)
            XCTAssertEqual(tokenizedPayment!.localizedDescription, "a description")
            XCTAssertEqual(tokenizedPayment!.nonce, "an-apple-pay-nonce")
            expectation.fulfill()
        }

        XCTAssertEqual(mockClient.lastPOSTPath, "v1/payment_methods/apple_payment_tokens")

        waitForExpectationsWithTimeout(2, handler: nil)
    }
    
    // MARK: - Metadata
    
    func testMetaParameter_whenTokenizationIsSuccessful_isPOSTedToServer() {
        let mockAPIClient = MockAPIClient(authorization: "development_tokenization_key")!
        mockAPIClient.cannedConfigurationResponseBody = BTJSON(value: [
            "applePay" : [
                "status" : "production"
            ]
            ])
        let applePayClient = BTApplePayClient(APIClient: mockAPIClient)
        let payment = MockPKPayment()
        
        let expectation = expectationWithDescription("Tokenized card")
        applePayClient.tokenizeApplePayPayment(payment) { _ -> Void in
            expectation.fulfill()
        }
        
        waitForExpectationsWithTimeout(5, handler: nil)
        
        XCTAssertEqual(mockAPIClient.lastPOSTPath, "v1/payment_methods/apple_payment_tokens")
        guard let lastPostParameters = mockAPIClient.lastPOSTParameters else {
            XCTFail()
            return
        }
        let metaParameters = lastPostParameters["_meta"] as! NSDictionary
        XCTAssertEqual(metaParameters["source"] as? String, "unknown")
        XCTAssertEqual(metaParameters["integration"] as? String, "custom")
        XCTAssertEqual(metaParameters["sessionId"] as? String, mockAPIClient.metadata.sessionId)
    }

    class MockPKPaymentToken : PKPaymentToken {
        override var paymentData : NSData {
            get {
                return NSData()
            }
        }
        override var transactionIdentifier : String {
            get {
                return "transaction-id"
            }
        }
        override var paymentInstrumentName : String {
            get {
                return "payment-instrument-name"
            }
        }
        override var paymentNetwork : String {
            get {
                return "payment-network"
            }
        }
    }

    class MockPKPayment : PKPayment {
        var overrideToken = MockPKPaymentToken()
        override var token : PKPaymentToken {
            get {
                return overrideToken
            }
        }
    }

}






