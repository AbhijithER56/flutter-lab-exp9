// Widget tests for UpdateBookScreen.
//
// These use an in-memory FakeFirebaseFirestore pre-filled the same way the
// "books" collection is filled in the Firebase Console. They check the UI,
// search and update logic only; the real Firestore is verified by
// tool/e2e_chrome_test.py.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_experiment_9_update_book_copies_firestore/update_book_screen.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late String pythonId;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateBookScreen(collection: firestore.collection('books')),
      ),
    );
    await tester.pumpAndSettle();
  }

  final titleField = find.widgetWithText(TextField, 'Enter Book Title');
  final copiesField = find.widgetWithText(TextField, 'Enter Updated Copies');

  Future<void> search(WidgetTester tester, String title) async {
    await tester.enterText(titleField, title);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
  }

  Future<void> update(WidgetTester tester, String copies) async {
    await tester.enterText(copiesField, copies);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
  }

  // The search text is also in the TextField, so look inside the result card.
  Finder inCard(String text) =>
      find.descendant(of: find.byType(Card), matching: find.text(text));

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    final books = firestore.collection('books');
    await books.add({
      'title': 'Flutter Basics',
      'author': 'John Smith',
      'copies': 5,
    });
    pythonId = (await books.add({
      'title': 'Python Programming',
      'author': 'David',
      'copies': 0,
    })).id;
    await books.add({
      'title': 'Artificial Intelligence',
      'author': 'Andrew',
      'copies': 3,
    });
  });

  testWidgets('shows title, both fields and both buttons', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Update Book Copies'), findsOneWidget);
    expect(titleField, findsOneWidget);
    expect(copiesField, findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('search shows current details of Python Programming', (
    tester,
  ) async {
    await pumpScreen(tester);
    await search(tester, 'Python Programming');

    expect(inCard('Python Programming'), findsOneWidget);
    expect(inCard('David'), findsOneWidget);
    expect(inCard('0'), findsOneWidget);
  });

  testWidgets('update changes only copies of the same document', (
    tester,
  ) async {
    await pumpScreen(tester);
    await search(tester, 'Python Programming');
    await update(tester, '5');

    expect(find.text('Book updated successfully'), findsOneWidget);
    expect(colorOf(tester, 'Book updated successfully'), Colors.green.shade700);
    expect(inCard('5'), findsOneWidget);

    final books = await firestore.collection('books').get();
    expect(books.docs, hasLength(3));
    final doc = await firestore.collection('books').doc(pythonId).get();
    expect(doc.data(), {
      'title': 'Python Programming',
      'author': 'David',
      'copies': 5,
    });
  });

  testWidgets('search is case-insensitive; Artificial Intelligence updates', (
    tester,
  ) async {
    await pumpScreen(tester);
    await search(tester, '  artificial   INTELLIGENCE ');
    expect(inCard('Andrew'), findsOneWidget);
    expect(inCard('3'), findsOneWidget);

    await update(tester, '8');
    expect(find.text('Book updated successfully'), findsOneWidget);
    expect(inCard('8'), findsOneWidget);
  });

  testWidgets('unknown title shows Book not found in red', (tester) async {
    await pumpScreen(tester);
    await search(tester, 'Data Structures');

    expect(find.text('Book not found'), findsOneWidget);
    expect(colorOf(tester, 'Book not found'), Colors.red);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('empty title shows validation message', (tester) async {
    await pumpScreen(tester);
    await search(tester, '   ');

    expect(find.text('Please enter a book title to search'), findsOneWidget);
  });

  testWidgets('update before search is rejected', (tester) async {
    await pumpScreen(tester);
    await update(tester, '4');

    expect(
      find.text('Please search for a book before updating'),
      findsOneWidget,
    );
  });

  testWidgets('empty and invalid copies are rejected without writing', (
    tester,
  ) async {
    await pumpScreen(tester);
    await search(tester, 'Flutter Basics');

    await update(tester, '');
    expect(
      find.text('Please enter the updated number of copies'),
      findsOneWidget,
    );

    for (final bad in ['-2', 'abc', '2.5']) {
      await update(tester, bad);
      expect(
        find.text('Copies must be a whole number (0 or more)'),
        findsOneWidget,
      );
    }

    final books = await firestore.collection('books').get();
    final flutter = books.docs.firstWhere(
      (d) => d['title'] == 'Flutter Basics',
    );
    expect(flutter['copies'], 5);
  });
}
