// Run: dart run example/shelf_example.dart   (PORT=8080 by default)
// Then open http://localhost:8080/ and http://localhost:8080/?guest=1
import 'dart:io';

import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class User {
  User(this.name, this.email, {this.isAdmin = false});
  final String name;
  final String email;
  final bool isAdmin;

  Map<String, Object?> toJson() => {
    'name': name,
    'email': email,
    'isAdmin': isAdmin,
  };
}

Future<void> main() async {
  final views = p.join(p.dirname(Platform.script.toFilePath()), 'views');
  final khnum =
      Khnum(
          viewsPath: views,
          environment: TemplateEnvironment.development, // reloads edited files
          missingVariables: MissingVariables.throwError,
        )
        ..share('appName', 'Acme')
        ..helper(
          'money',
          (args) => '\$${(args.first as num).toStringAsFixed(2)}',
        );

  Future<Response> home(Request request) async {
    final guest = request.url.queryParameters.containsKey('guest');
    final html = await khnum.render('home', {
      'title': 'Home',
      'heading': 'Dashboard',
      'currentPath': '/${request.url.path}',
      'links': [
        {'href': '/', 'label': 'Home'},
        {'href': '/?guest=1', 'label': 'As guest'},
      ],
      'user': guest ? null : User('Ann', 'ann@example.com', isAdmin: true),
      'orders': guest
          ? []
          : [
              {'id': 1, 'total': 19.99, 'status': 'shipped'},
              {'id': 2, 'total': 5, 'status': 'pending'},
            ],
      'now': DateTime.now().toIso8601String(),
    });
    return Response.ok(
      html,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  final pipeline = const Pipeline().addMiddleware(logRequests()).addHandler((
    request,
  ) {
    if (request.url.path.isEmpty) return home(request);
    return Response.notFound('Not found');
  });

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(pipeline, 'localhost', port);
  print('Listening on http://${server.address.host}:${server.port}');
}
