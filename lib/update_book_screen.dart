import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Searches the Cloud Firestore collection "books" by title and updates the
/// "copies" field of the matching document. Books are added manually in the
/// Firebase Console; this screen never adds new books and never changes the
/// title or author.
class UpdateBookScreen extends StatefulWidget {
  const UpdateBookScreen({super.key, this.collection});

  /// Optional collection override (used by tests with a fake Firestore).
  /// Defaults to FirebaseFirestore.instance.collection("books").
  final CollectionReference? collection;

  @override
  State<UpdateBookScreen> createState() => _UpdateBookScreenState();
}

class _UpdateBookScreenState extends State<UpdateBookScreen> {
  final _titlecontroller = TextEditingController();
  final _copiescontroller = TextEditingController();

  // Database instance
  late final CollectionReference books =
      widget.collection ?? FirebaseFirestore.instance.collection("books");

  // Reference to the document found by the last search; Update writes here.
  DocumentReference? _bookRef;
  Map<String, dynamic>? _book;

  bool _searching = false;
  bool _updating = false;
  String _message = "";
  bool _isError = false;

  bool get _busy => _searching || _updating;

  @override
  void dispose() {
    _titlecontroller.dispose();
    _copiescontroller.dispose();
    super.dispose();
  }

  // Trim, collapse repeated spaces and lowercase, so "  python   PROGRAMMING "
  // matches "Python Programming".
  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  // Console users may store copies as a number or as text; accept both.
  static int? _parseCopies(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  void _showMessage(String message, {required bool isError}) {
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  String _firebaseError(Object e) => e is FirebaseException
      ? "Firebase error (${e.code}): ${e.message ?? 'unknown'}"
      : "Error: $e";

  // READ: fetch the "books" collection and keep the document whose title
  // matches the search text. Firestore queries are case-sensitive, so the
  // matching is done here.
  Future<void> _searchBook() async {
    FocusScope.of(context).unfocus();
    final query = _normalize(_titlecontroller.text);

    if (query.isEmpty) {
      setState(() {
        _book = null;
        _bookRef = null;
      });
      _showMessage("Please enter a book title to search", isError: true);
      return;
    }

    setState(() {
      _searching = true;
      _book = null;
      _bookRef = null;
      _message = "";
    });

    try {
      final snapshot = await books.get();
      QueryDocumentSnapshot? match;
      for (final doc in snapshot.docs) {
        // Read defensively: documents added by hand may be missing a field.
        final data = doc.data() as Map<String, dynamic>? ?? {};
        if (_normalize("${data['title'] ?? ''}") == query) {
          match = doc;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _bookRef = match?.reference;
        _book = match?.data() as Map<String, dynamic>?;
      });
      if (match == null) _showMessage("Book not found", isError: true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_firebaseError(e), isError: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // UPDATE: change only the "copies" field of the searched document.
  // DocumentReference.update() fails if the document does not exist, so it
  // can never create a new book.
  Future<void> _updateCopies() async {
    FocusScope.of(context).unfocus();
    final ref = _bookRef;

    if (ref == null) {
      _showMessage("Please search for a book before updating", isError: true);
      return;
    }

    final text = _copiescontroller.text.trim();
    if (text.isEmpty) {
      _showMessage("Please enter the updated number of copies", isError: true);
      return;
    }
    final copies = int.tryParse(text);
    if (copies == null || copies < 0) {
      _showMessage(
        "Copies must be a whole number (0 or more)",
        isError: true,
      );
      return;
    }

    setState(() {
      _updating = true;
      _message = "";
    });

    try {
      await ref.update({'copies': copies});
      // Read the document back so the card shows what Firestore now stores.
      final updated = await ref.get();
      if (!mounted) return;
      setState(() {
        _book = updated.data() as Map<String, dynamic>?;
      });
      _copiescontroller.clear();
      _showMessage("Book updated successfully", isError: false);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_firebaseError(e), isError: true);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.deepPurple.shade200,
          disabledForegroundColor: Colors.white,
        ),
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _buildInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titlecontroller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            if (!_busy) _searchBook();
          },
          decoration: const InputDecoration(
            labelText: "Enter Book Title",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.menu_book),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _copiescontroller,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_busy) _updateCopies();
          },
          decoration: const InputDecoration(
            labelText: "Enter Updated Copies",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildButton(
                label: "Search",
                icon: Icons.search,
                loading: _searching,
                onPressed: _searchBook,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildButton(
                label: "Update",
                icon: Icons.edit,
                loading: _updating,
                onPressed: _updateCopies,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessage() {
    final color = _isError ? Colors.red : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    final copies = _parseCopies(book['copies']);
    return Card(
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("Title", "${book['title'] ?? '-'}"),
            _buildDetailRow("Author", "${book['author'] ?? '-'}"),
            _buildDetailRow("Copies Available", "${copies ?? '-'}"),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Text("Update Book Copies"),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          // Keep the layout readable on tablets / landscape.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInputs(),
                  const SizedBox(height: 20),
                  if (_message.isNotEmpty) ...[
                    _buildMessage(),
                    const SizedBox(height: 12),
                  ],
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_book != null)
                    _buildBookCard(_book!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
