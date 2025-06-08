import 'package:rich_stdout/rich_stdout.dart';
import 'package:mysql1/mysql1.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:io';

class Server {
  /// the port number of the server to run on
  int port;

  /// the ip address of the server to run on
  String ip;

  /// a map of file extention to content types
  final Map<String, ContentType> contentTypeMap = {
    'html': ContentType.html,
    'css': ContentType('text', 'css', charset: 'utf-8'),
    'js': ContentType('application', 'javascript', charset: 'utf-8'),
    'json': ContentType('application', 'json', charset: 'utf-8'),
    
    'binary': ContentType('application', 'octet-stream'),
    'bin': ContentType.binary,
    
    'xml': ContentType('application', 'xml', charset: 'utf-8'),
    'text': ContentType('text', 'plain', charset: 'utf-8'),
    'txt': ContentType.text,
    
    'png': ContentType('image', 'png'),
    'jpeg': ContentType('image', 'jpeg'),
    'gif': ContentType('image', 'gif'),
    'svg': ContentType.parse('image/svg+xml'),
    'ico': ContentType('image', 'x-icon'),

    'mp3': ContentType('audio', 'mpeg'),
    'wav': ContentType('audio', 'wav'),
    'ogg': ContentType('audio', 'ogg'),
    'webm': ContentType('video', 'webm'),

    'm4a': ContentType('audio', 'x-m4a'),
    'pdf': ContentType('application', 'pdf'),
  };

  /// a stdout wrapper
  final _terminal = Terminal();

  /// contains all routes for GET
  final Map<String, Function(HttpRequest)> _getRoutes = {};

  /// contains all routes for POST
  final Map<String, Function(HttpRequest)> _postRoutes = {};

  /// contains all routes for DELETE
  final Map<String, Function(HttpRequest)> _deleteRoutes = {};

  /// contains all routes for PUT
  final Map<String, Function(HttpRequest)> _putRoutes = {};

  /// a connection to a mySQL
  MySqlConnection? connection;

  /// the default action to take when no there is no found route
  Function(HttpRequest) _defaultAction = (HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.html
      ..write('<b>404 page ${request.uri.path} not found')
      ..close();
  };

  /// sates weather the sever is able to error non-sql functions
  bool canError;
  
  /// # Sever
  /// this is a webserver built in dart.
  /// this is used to handle incoming requests
  /// set `ip` to something other than `127.0.0.1` if you do not want to host on localhost
  /// set `port` to any int default is `3000`
  /// set `canError` to false if you do not want the server to error in non-sql related issues
  Server({this.ip = '127.0.0.1', this.port = 3000, this.canError = true});

  /// starts the server on the desired ip
  Future<void> start() async {
    final server = await HttpServer.bind(ip, port);
    _terminal.info('Listening on http://${server.address.address}:${server.port}');
    
    await for (HttpRequest request in server) {
      _terminal.info('Incoming request for ${request.method} ${request.uri.path}');

      String path = request.uri.path;
      if (path.isEmpty) {
        error('Path $path is empty');
      }
      
      while (path.endsWith('/') && path != '/') {
        path = path.substring(0, path.length-1);
      }

      String method = request.method;

      if (method == 'GET' && _getRoutes.containsKey(path)) {
        _getRoutes[path]!(request);
      } else if (method == 'POST' && _postRoutes.containsKey(path)) {
        _postRoutes[path]!(request);
      } else if (method == 'DELETE' && _deleteRoutes.containsKey(path)) {
        _deleteRoutes[path]!(request);
      } else if (method == 'PUT' && _putRoutes.containsKey(path)) {
        _putRoutes[path]!(request);
      } else {
        _defaultAction(request);
      }
      try {
      } catch (e) {
        _terminal.error(e.toString());

        request.response.close();
      }
    }
  }

  /// adds a POST route to the server
  void post(String route, FutureOr<void> Function(HttpRequest) action) {
    route = _normaliseRoute(route); // Use the helper
    if (_postRoutes.containsKey(route)) {
      error('route "$route" for POST already taken');
    }
    _postRoutes[route] = action; // Use direct assignment
  }

  /// adds a DELETE route to the server
  void delete(String route, FutureOr<void> Function(HttpRequest) action) {
    route = _normaliseRoute(route);
    if (_deleteRoutes.containsKey(route)) {
      error('route "$route" for DELETE already taken');
    }
    _deleteRoutes[route] = action;
  }

  /// adds a PUT route to the server
  void put(String route, FutureOr<void> Function(HttpRequest) action) {
    route = _normaliseRoute(route);
    if (_putRoutes.containsKey(route)) {
      error('route "$route" for PUT already taken');
    }
    _putRoutes[route] = action;
  }

  // adds a GET route to the server
  void get(String route, FutureOr<void> Function(HttpRequest) action) {
    route = _normaliseRoute(route);
    if (_getRoutes.containsKey(route)) {
      error('route "$route" for GET already taken');
    }
    _getRoutes[route] = action;
  }

  /// Helper method to normalises routes
  String _normaliseRoute(String route) {
    if (route.isEmpty) {
      throw ArgumentError('Route cannot be empty');
    }
    while (route.endsWith('/') && route != '/') {
      route = route.substring(0, route.length - 1);
    }
    return route;
  }

  /// makes an SQL connection with the server
  /// call it with
  /// ```dart
  /// var result = server.query('my sql query');
  /// ```
  Future<void> makeSqlConnection(String database, {host='localhost', port=3306, user='root', password=''}) async {
    final settings = ConnectionSettings(
      host: host,
      port: port,
      user: user,
      password: password,
      db: database,
    );

    try {
      connection = await MySqlConnection.connect(settings);
      _terminal.success('Connected to database');
    } catch (e) {
      error('Failed to connect to database: $e');
    }
  }

  /// queries the database attached to the server
  /// this will error if there is no attached database
  Future<Results> query(String query, [List<Object>? values]) async {
    if (connection == null) {
      _terminal.warning('No SQL connection has been made');
      throw StateError('No SQL connection established.'); 
    }
    return await connection!.query(query, values);
  }

  /// takes over a request and returns a HTML file from a path
  /// specify for a path to not be absolute to remove the leading `/`(s)
  /// the first argument is the request it return too
  /// this function will also close the request
  /// ```dart
  /// server.get('/home', (HttpRequest request) {
  ///   server.returnFile(request, '/web/home/', absolute: false);
  /// });
  /// ```
  void returnFile(
    HttpRequest request, String path,
    {
      int? statusCode,
      ContentType? contentType,
      String defaultPath = 'web/pages/page-not-found.html',
      List<String> folders = const [],
    }
  ) async {
    String safePath = p.normalize(path);

    if (safePath.contains('..') || safePath.startsWith('/') || safePath.startsWith('\\')) {
        request.response
          ..statusCode = HttpStatus.forbidden 
          ..write('<h1>Invalid path specified.</h1>')
          ..close();
        _terminal.error('Attempted path traversal detected: $path');
        return;
    }

    String fullPath = p.joinAll(folders.toList() + [safePath]);
      _terminal.info('Attempting to serve: $fullPath');

    if (Directory(fullPath).existsSync()) {
      fullPath = '$fullPath/index.html';
    }

    if (!File(fullPath).existsSync()) {
      _terminal.error('No file found under path: $fullPath');
      returnFile(request, defaultPath);
      return;
    }

    if (await File(fullPath).exists()) { 
      try {
        request.response
        ..statusCode = statusCode ?? HttpStatus.ok
        ..headers.contentType = contentType ?? (contentTypeMap[fullPath.split('.').last.toLowerCase()] ?? ContentType.binary)
        ..write(File(fullPath).readAsStringSync())
        ..close();
      } catch (e) {
        _terminal.error('Error reading file $fullPath: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('<h1>Server error reading page</h1>')
          ..close();
      }
    } else {
      _terminal.warning('Could not find $fullPath serving  page not found');
      if (defaultPath.isNotEmpty) {
        returnFile(request, defaultPath);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    }
  }

  /// this is a method to makes the server error
  /// it also handles the incoming request 
  void error(String message, [HttpRequest? request]) {
    _terminal.error(message);

    if (request != null) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    }
    
    if (canError) {
      throw Error();
    }
  }

  /// this will send a logging message to the terminal
  void log(dynamic message) {
    _terminal.info(message.toString());
  }

  /// this is to set a new function for the default action
  set defaultAction(Function(HttpRequest) action) {
    _defaultAction = action;
  }
}