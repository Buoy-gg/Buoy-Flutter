// Buoy route inspector — wiring:
// 1. Add BuoyRouteObserver.instance to your GoRouter's `observers`.
// 2. registerBuoyRoutes(router: _router) registers the tool + adapter and hands
//    over the router (for the sitemap + remote navigate).
// 3. BuoyDevTools mounts the in-app menu and starts desktop sync.
import 'package:buoy_routes/buoy_routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final _router = GoRouter(
  observers: [BuoyRouteObserver.instance],
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push('/details/42'),
            child: const Text('Open details'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/details/:id',
      builder: (context, state) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Detail ${state.pathParameters['id']}')),
      ),
    ),
  ],
);

void main() {
  if (kDebugMode) registerBuoyRoutes(router: _router);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      builder: (context, child) => BuoyDevTools(
        deviceName: 'My App',
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
