import Foundation

public func log(_ object: Any, flush: Bool = false) {
    fputs("\(object)\n", stderr)
    if flush {
        fflush(stderr)
    }
}

public typealias JSONDictionary = [String: Any]

struct InvocationError: Codable {
    let errorMessage: String
}

public class Runtime {
    var counter = 0
    let urlSession: URLSession
    let awsLambdaRuntimeAPI: String
    let handlerName: String
    var handlers: [String: Handler]
    
    public init() throws {
        self.urlSession = URLSession.shared
        self.handlers = [:]
        
        let environment = ProcessInfo.processInfo.environment
        guard let awsLambdaRuntimeAPI = environment["AWS_LAMBDA_RUNTIME_API"],
           let handler = environment["_HANDLER"] else {
              throw RuntimeError.missingEnvironmentVariables
        }

        guard let periodIndex = handler.index(of: ".") else {
            throw RuntimeError.invalidHandlerName
        }

        self.awsLambdaRuntimeAPI = awsLambdaRuntimeAPI
        self.handlerName = String(handler[handler.index(after: periodIndex)...])
    }
    
    func getNextInvocation() throws -> (inputData: Data, requestId: String, invokedFunctionArn: String) {
        let getNextInvocationEndpoint = URL(string: "http://\(awsLambdaRuntimeAPI)/2018-06-01/runtime/invocation/next")!
        let (optData, optResponse, optError) = urlSession.synchronousDataTask(with: getNextInvocationEndpoint)
        
        guard optError == nil else {
            throw RuntimeError.endpointError(optError!.localizedDescription)
        }
        
        guard let inputData = optData else {
            throw RuntimeError.missingData
        }
        
        let httpResponse = optResponse as! HTTPURLResponse
        let requestId = httpResponse.allHeaderFields["Lambda-Runtime-Aws-Request-Id"] as! String
        let invokedFunctionArn = httpResponse.allHeaderFields["Lambda-Runtime-Invoked-Function-Arn"] as! String
        return (inputData: inputData, requestId: requestId, invokedFunctionArn: invokedFunctionArn)
    }
    
    func postInvocationResponse(for requestId: String, httpBody: Data) {
        let postInvocationResponseEndpoint = URL(string: "http://\(awsLambdaRuntimeAPI)/2018-06-01/runtime/invocation/\(requestId)/response")!
        var urlRequest = URLRequest(url: postInvocationResponseEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = httpBody
        _ = urlSession.synchronousDataTask(with: urlRequest)
    }

    func postInvocationError(for requestId: String, error: Error) {
        let invocationError = InvocationError(errorMessage: String(describing: error))
        let jsonEncoder = JSONEncoder()
        let httpBody = try! jsonEncoder.encode(invocationError)

        let postInvocationErrorEndpoint = URL(string: "http://\(awsLambdaRuntimeAPI)/2018-06-01/runtime/invocation/\(requestId)/error")!
        var urlRequest = URLRequest(url: postInvocationErrorEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = httpBody
        _ = urlSession.synchronousDataTask(with: urlRequest)
    }

    func createContext(requestId: String, invokedFunctionArn: String) -> Context {
        let environment = ProcessInfo.processInfo.environment
        let functionName = environment["AWS_LAMBDA_FUNCTION_NAME"] ?? ""
        let functionVersion = environment["AWS_LAMBDA_FUNCTION_VERSION"] ?? ""
        let logGroupName = environment["AWS_LAMBDA_LOG_GROUP_NAME"] ?? ""
        let logStreamName = environment["AWS_LAMBDA_LOG_STREAM_NAME"] ?? ""
        return Context(functionName: functionName,
                        functionVersion: functionVersion,
                        logGroupName: logGroupName,
                        logStreamName: logStreamName,
                        awsRequestId: requestId,
                        invokedFunctionArn: invokedFunctionArn)
    }

    public func registerLambda(_ name: String, handlerFunction: @escaping (JSONDictionary, Context) throws -> JSONDictionary) {
        let handler = JSONSerializationHandler(handlerFunction: handlerFunction)
        handlers[name] = handler
    }

    public func registerLambda<Input: Decodable, Output: Encodable>(_ name: String, handlerFunction: @escaping (Input, Context) throws -> Output) {
        let handler = CodableHandler(handlerFunction: handlerFunction)
        handlers[name] = handler
    }
    
    public func start() throws {
        while true {
            let (inputData, requestId, invokedFunctionArn) = try getNextInvocation()
            counter += 1
            log("Invocation-Counter: \(counter)")

            guard let handler = handlers[handlerName] else {
                throw RuntimeError.unknownLambdaHandler
            }

            let context = createContext(requestId: requestId, invokedFunctionArn: invokedFunctionArn)

            do {
                let outputData = try handler.apply(inputData: inputData, context: context)
                postInvocationResponse(for: requestId, httpBody: outputData)
            } catch {
                postInvocationError(for: requestId, error: error)
            }
        }
    }
}
