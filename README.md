# aws-lambda-swift

The goal of this project is to implement a custom AWS Lambda Runtime for the Swift programming language.

### Step 1: Implement your lambda handler function
`ExampleLambda` is an SPM package with a single, executable target that implements the lambda handler function.
This package depends on the `AWSLambdaSwift` package which produces a library that contains the actual runtime.
In the main.swift file of the `ExampleLambda` executable we import the AWSLambdaSwift library, instantiate the
`Runtime` class and then register our handler function. Finally, we start the runtime:

```swift
import AWSLambdaSwift

func suareNumber(input: JSONDictionary) -> JSONDictionary {
    guard let number = input["number"] as? Double else {
        return ["success": false]
    }

    let squaredNumber = number * number
    return ["success": true, "result": squaredNumber]
}

let runtime = try Runtime()
runtime.registerLambda("squareNumber", handler: suareNumber)
try runtime.start()
```

At the moment, the handler functions need to have a single parameter of type `JSONDictionary` and they also need to
return a `JSONDictionary`. This type is just a typealias for the type `Dictionary<String, Any>`.

### Step 2: Build the lambda
AWS Lambdas run on Amazon Linux (see [https://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html](https://docs.aws.amazon.com/lambda/latest/dg/current-supported-versions.html)).
This means that we can't just run `swift build` on macOS because that will produce a macOS executable which doesn't run on Linux. Instead, I have used Docker to build the `ExampleLambda` package.
Execute the following command to build the `ExampleLambda` package and bundle it in a zip file together with the `bootstrap` file.

```bash
make package_lambda
```

To see how this works, have a look at the `Makefile`.

### Step 3: Setup the layer
We now have a Linux executable. However, this executable dynamically links to the Swift standard library and a bunch of other libraries (Foundation, Grand Central Dispatch, Glibc, etc). Those
libraries are not available on Amazon Linux.

### Step 4: Setup the lambda

### Step 5: Run the lambda