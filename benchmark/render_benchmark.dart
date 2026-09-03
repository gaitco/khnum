// Run: dart run benchmark/render_benchmark.dart
// A realistic page: layout + nav partial + two components + a 50-row table,
// rendered repeatedly from the in-memory AST cache (production mode).
import 'package:khnum/khnum.dart';

void main() {
  final khnum =
      Khnum.inMemory({
          'layouts.app': '''
<!DOCTYPE html>
<html><head><title>@yield("title", "App")</title></head>
<body>
@include("partials.nav")
<main>@yield("content")</main>
<footer>{{ appName }} - {{ year }}</footer>
</body></html>''',
          'partials.nav': '''
<nav>@foreach(links as link)<a href="{{ link.href }}">{{ link.label }}</a>@endforeach</nav>''',
          'components.alert': '''
@props({"type": "info"})<div {{ attributes.merge({"class": "alert alert-" + type}) }}>{{ slot }}</div>''',
          'components.row': '''
<tr class="{{ loop.odd ? "odd" : "even" }}"><td>{{ order.id }}</td><td>{{ order.customer.name }}</td><td>{{ money(order.total) }}</td><td>@if(order.paid)paid@else due@endif</td></tr>''',
          'orders.index': '''
@extends("layouts.app")
@section("title", "Orders: " + count(orders))
@section("content")
<x-alert type="success">{{ count(orders) }} orders loaded for {{ user.name }}.</x-alert>
<table>
@foreach(orders as order)
<x-row :order="order" :loop="loop" />
@endforeach
</table>
@unless(orders)<p>No orders.</p>@endunless
@endsection''',
        }, environment: TemplateEnvironment.production)
        ..share('appName', 'Acme')
        ..helper('money', (a) => '\$${(a.first as num).toStringAsFixed(2)}');

  final data = {
    'year': 2026,
    'user': {'name': 'Ann <admin>'},
    'links': [
      for (var i = 0; i < 5; i++) {'href': '/p/$i', 'label': 'Page $i'},
    ],
    'orders': [
      for (var i = 0; i < 50; i++)
        {
          'id': i,
          'customer': {'name': 'Customer & Co $i'},
          'total': i * 9.99,
          'paid': i.isEven,
        },
    ],
  };

  final html = khnum.renderSync('orders.index', data);
  print('Output: ${html.length} bytes, ${'<tr'.allMatches(html).length} rows');

  const warmup = 200;
  const iterations = 2000;
  for (var i = 0; i < warmup; i++) {
    khnum.renderSync('orders.index', data);
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    khnum.renderSync('orders.index', data);
  }
  watch.stop();
  final perRender = watch.elapsedMicroseconds / iterations;
  print(
    'Render: ${perRender.toStringAsFixed(1)} us/render, '
    '${(1e6 / perRender).toStringAsFixed(0)} renders/s',
  );
}
