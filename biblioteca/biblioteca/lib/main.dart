import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart'
    as p; // Renomeado para 'p' para evitar conflito com BuildContext

// Constantes
const String _tableBook = 'book';
const String _columnId = '_id';
const String _columnTitle = 'title';
const String _columnAuthor = 'author';
const String _columnGenre = 'genre';
const String _columnStatus = 'status';
const String _columnRating = 'rating';

// --- CAMADA DE MODELO (MODEL) ---

class Book {
  int? id;
  String title;
  String author;
  String genre;
  String status; // 'Lido', 'Lendo', 'Não Lido'
  int rating; // 0 a 5

  Book({
    this.id,
    required this.title,
    required this.author,
    required this.genre,
    required this.status,
    required this.rating,
  });

  // Converte um objeto Book em um Map (para salvar no DB)
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      _columnTitle: title,
      _columnAuthor: author,
      _columnGenre: genre,
      _columnStatus: status,
      _columnRating: rating,
    };
    if (id != null) {
      map[_columnId] = id;
    }
    return map;
  }

  // Converte um Map em um objeto Book (para ler do DB)
  Book.fromMap(Map<String, dynamic> map)
    : id = map[_columnId] as int?,
      title = map[_columnTitle] as String,
      author = map[_columnAuthor] as String,
      genre = map[_columnGenre] as String,
      status = map[_columnStatus] as String,
      rating = map[_columnRating] as int;
}

// --- CAMADA DE ACESSO A DADOS (DAO) ---

class BookDao {
  static final BookDao _instance = BookDao._internal();
  static Database? _database;

  factory BookDao() {
    return _instance;
  }

  BookDao._internal();

  // Getter para o banco de dados
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  // Inicializa o banco de dados e cria a tabela
  Future<Database> _initDb() async {
    String databasesPath = await getDatabasesPath();
    String path = p.join(databasesPath, 'library.db'); // Usando 'p.join'

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableBook (
            $_columnId INTEGER PRIMARY KEY AUTOINCREMENT,
            $_columnTitle TEXT NOT NULL,
            $_columnAuthor TEXT NOT NULL,
            $_columnGenre TEXT NOT NULL,
            $_columnStatus TEXT NOT NULL,
            $_columnRating INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // Insere um novo livro
  Future<int> insertBook(Book book) async {
    final db = await database;
    return await db.insert(_tableBook, book.toMap());
  }

  // Atualiza um livro existente
  Future<int> updateBook(Book book) async {
    final db = await database;
    return await db.update(
      _tableBook,
      book.toMap(),
      where: '$_columnId = ?',
      whereArgs: [book.id],
    );
  }

  // Deleta um livro
  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.delete(
      _tableBook,
      where: '$_columnId = ?',
      whereArgs: [id],
    );
  }

  // Obtém todos os livros, opcionalmente filtrados por status
  Future<List<Book>> getBooks({String? status}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    if (status == null || status == 'Todos') {
      maps = await db.query(_tableBook);
    } else {
      maps = await db.query(
        _tableBook,
        where: '$_columnStatus = ?',
        whereArgs: [status],
      );
    }

    if (maps.isEmpty) {
      return [];
    }

    return List.generate(maps.length, (i) {
      return Book.fromMap(maps[i]);
    });
  }
}

// --- WIDGETS DE UI ---

void main() {
  // Garante que a ligação do Flutter (binding) está inicializada antes de rodar o app.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LibraryApp());
}

class LibraryApp extends StatelessWidget {
  const LibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minha Biblioteca Pessoal',
      theme: ThemeData(primarySwatch: Colors.blueGrey, useMaterial3: true),
      home: const BookListScreen(),
    );
  }
}

// Widget para exibir as estrelas de classificação
class StarRating extends StatelessWidget {
  final int rating;
  final double size;
  const StarRating({super.key, required this.rating, this.size = 20.0});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: size,
        );
      }),
    );
  }
}

// --- TELA PRINCIPAL: LISTAGEM E FILTRO ---

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  final BookDao _bookDao = BookDao();
  List<Book> _books = [];
  String _filterStatus =
      'Todos'; // Opções: 'Todos', 'Lido', 'Lendo', 'Não Lido'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    setState(() {
      _isLoading = true;
    });
    // O status é passado para a DAO, exceto se for 'Todos' (null)
    final books = await _bookDao.getBooks(
      status: _filterStatus == 'Todos' ? null : _filterStatus,
    );
    setState(() {
      _books = books;
      _isLoading = false;
    });
  }

  void _navigateToForm({Book? book}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BookFormScreen(book: book)),
    );

    // Se o formulário retornou true (significa que houve uma alteração)
    if (result == true) {
      _loadBooks();
    }
  }

  void _confirmDelete(Book book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza de que deseja excluir o livro "${book.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await _bookDao.deleteBook(book.id!);
              _loadBooks();
              if (mounted) Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha Biblioteca'),
        actions: [
          // Dropdown para filtro de status
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterStatus,
                icon: const Icon(Icons.filter_list),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _filterStatus = newValue;
                    });
                    _loadBooks();
                  }
                },
                items: <String>['Todos', 'Lido', 'Lendo', 'Não Lido']
                    .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    })
                    .toList(),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu_book, size: 80, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(
                    _filterStatus == 'Todos'
                        ? 'Nenhum livro cadastrado.'
                        : 'Nenhum livro com status: $_filterStatus',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _navigateToForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar Livro'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor,
                      child: Text(
                        book.title[0],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      book.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Autor: ${book.author}'),
                        Text('Gênero: ${book.genre}'),
                        Row(
                          children: [
                            const Text('Status: '),
                            Chip(
                              label: Text(
                                book.status,
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: book.status == 'Lido'
                                  ? Colors.green.shade100
                                  : book.status == 'Lendo'
                                  ? Colors.blue.shade100
                                  : Colors.red.shade100,
                            ),
                          ],
                        ),
                        StarRating(rating: book.rating),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _navigateToForm(book: book),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDelete(book),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToForm(),
        label: const Text('Novo Livro'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

// --- TELA DE CADASTRO/EDIÇÃO (FORMULÁRIO) ---

class BookFormScreen extends StatefulWidget {
  final Book? book; // Livro a ser editado (opcional)

  const BookFormScreen({super.key, this.book});

  @override
  State<BookFormScreen> createState() => _BookFormScreenState();
}

class _BookFormScreenState extends State<BookFormScreen> {
  final BookDao _bookDao = BookDao();
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _genreController = TextEditingController();

  // Estados do formulário
  String? _selectedStatus;
  int _selectedRating = 0;

  // Opções
  static const List<String> _statusOptions = ['Lido', 'Lendo', 'Não Lido'];
  static const List<String> _genreOptions = [
    'Ficção',
    'Não Ficção',
    'Fantasia',
    'Ciência',
    'Romance',
    'Suspense',
    'Biografia',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();
    // Preenche o formulário se um livro for passado para edição
    if (widget.book != null) {
      _titleController.text = widget.book!.title;
      _authorController.text = widget.book!.author;
      _genreController.text = widget.book!.genre;
      _selectedStatus = widget.book!.status;
      _selectedRating = widget.book!.rating;
    } else {
      // Valor padrão para novo livro
      _selectedStatus = _statusOptions.first;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  Future<void> _saveBook() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final newBook = Book(
        id: widget.book?.id,
        title: _titleController.text,
        author: _authorController.text,
        genre: _genreController.text,
        status: _selectedStatus!,
        rating: _selectedRating,
      );

      if (newBook.id == null) {
        // Inserção
        await _bookDao.insertBook(newBook);
        _showMessage('Livro cadastrado com sucesso!');
      } else {
        // Atualização
        await _bookDao.updateBook(newBook);
        _showMessage('Livro atualizado com sucesso!');
      }

      // Retorna true para a tela anterior para forçar um recarregamento da lista
      if (mounted) Navigator.pop(context, true);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.book != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar Livro' : 'Novo Livro')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Título
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título do Livro',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  prefixIcon: Icon(Icons.book),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira o título.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // Autor
              TextFormField(
                controller: _authorController,
                decoration: const InputDecoration(
                  labelText: 'Autor(a)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira o autor.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // Gênero (DropdownButtonFormField)
              DropdownButtonFormField<String>(
                value: _genreController.text.isNotEmpty
                    ? _genreController.text
                    : _genreOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Gênero',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _genreOptions.map((String genre) {
                  return DropdownMenuItem<String>(
                    value: genre,
                    child: Text(genre),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    _genreController.text = newValue;
                  }
                },
                onSaved: (value) {
                  _genreController.text = value ?? _genreOptions.first;
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, selecione o gênero.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // Status de Leitura (DropdownButtonFormField)
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status de Leitura',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  prefixIcon: Icon(Icons.bookmark),
                ),
                items: _statusOptions.map((String status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(status),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedStatus = newValue;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, selecione o status.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 25),

              // Nota Pessoal (Rating)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nota Pessoal (0-5):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      return IconButton(
                        icon: Icon(
                          index <= _selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 35,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedRating = index;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 25),
                ],
              ),

              // Botão Salvar
              FilledButton.icon(
                onPressed: _saveBook,
                icon: Icon(isEditing ? Icons.save : Icons.add),
                label: Text(
                  isEditing ? 'Salvar Alterações' : 'Cadastrar Livro',
                  style: const TextStyle(fontSize: 18),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
