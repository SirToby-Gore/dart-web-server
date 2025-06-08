# Example usage
```dart
final server = basic_web_server.Server(port: 2000)
    ..get('/', (HttpRequest request) {
    request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write([
            '<style>body {background-color: navy; color: white; font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0;}</style>',
            '<div><h1>Welcome to using webserver!</h1><p>This is the example page.</p></div>',
        ].join('\n'))
        ..close();
    })

    ..start();
```