// Importações necessárias
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // <-- CORREÇÃO: Adicionando prefixo 'p'
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; // Para o Desafio Extra
import 'package:flutter/foundation.dart'; // Para kIsWeb
// Removendo importações de FFI e dart:io para estabilidade Web

// -----------------------------------------------------------
// 1. Definição do Modelo de Dados (Transaction)
// -----------------------------------------------------------

class Transaction {
  final int? id;
  final String description;
  final double value;
  final DateTime date;
  final String category;

  Transaction({
    this.id,
    required this.description,
    required this.value,
    required this.date,
    required this.category,
  });

  // Converte a Transação para um Mapa (útil para inserção no DB)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'value': value,
      'date': date.toIso8601String(),
      'category': category,
    };
  }

  // Cria uma Transação a partir de um Mapa do DB
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      description: map['description'],
      value: map['value'],
      date: DateTime.parse(map['date']),
      category: map['category'],
    );
  }
}

// -----------------------------------------------------------
// 2. Gerenciador do Banco de Dados (DatabaseHelper)
// -----------------------------------------------------------

class DatabaseHelper {
  static Database? _database;
  static final DatabaseHelper instance = DatabaseHelper._();

  DatabaseHelper._();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('transactions.db');
    return _database!;
  }

  // Inicializa e abre o banco de dados
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath); // <-- CORREÇÃO: Usando p.join

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  // Cria a tabela de transações
  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const doubleType = 'REAL NOT NULL';

    await db.execute('''
      CREATE TABLE transactions (
        id $idType,
        description $textType,
        value $doubleType,
        date $textType,
        category $textType
      )
    ''');
  }

  // CRUD: Inserir ou Atualizar (upsert)
  Future<int> insertOrUpdateTransaction(Transaction transaction) async {
    final db = await instance.database;
    if (transaction.id != null) {
      return await db.update(
        'transactions',
        transaction.toMap(),
        where: 'id = ?',
        whereArgs: [transaction.id],
      );
    } else {
      return await db.insert('transactions', transaction.toMap());
    }
  }

  // CRUD: Listar todas as transações, ordenadas por data
  Future<List<Transaction>> getTransactions() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'date DESC',
    );

    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // CRUD: Excluir uma transação
  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // CRIA: Busca por descrição (usado para o campo de pesquisa)
  Future<List<Transaction>> searchTransactions(String query) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'description LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'date DESC',
    );

    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // CRIA: Cálculo do total gasto por categoria
  Future<Map<String, double>> getTotalsByCategory() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT category, SUM(value) as total
      FROM transactions
      GROUP BY category
    ''');

    Map<String, double> totals = {};
    for (var map in maps) {
      totals[map['category'] as String] = (map['total'] as double);
    }
    return totals;
  }
}

// -----------------------------------------------------------
// 3. Estrutura Principal do Aplicativo
// -----------------------------------------------------------

void main() {
  // Inicialização para garantir que o Flutter bindings esteja pronto antes de rodar o app
  WidgetsFlutterBinding.ensureInitialized();
  // NOTA: A inicialização específica do sqflite para Web/Desktop está sendo omitida
  // para evitar o erro de compilação/execução no Canvas.
  runApp(const ControleDeDespesasApp());
}

class ControleDeDespesasApp extends StatelessWidget {
  const ControleDeDespesasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle de Despesas',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blueGrey,
          accentColor: Colors.teal,
        ),
        useMaterial3: true,
      ),
      home: const ExpenseTrackerScreen(),
    );
  }
}

// -----------------------------------------------------------
// 4. Tela Principal (ExpenseTrackerScreen)
// -----------------------------------------------------------

class ExpenseTrackerScreen extends StatefulWidget {
  const ExpenseTrackerScreen({super.key});

  @override
  State<ExpenseTrackerScreen> createState() => _ExpenseTrackerScreenState();
}

class _ExpenseTrackerScreenState extends State<ExpenseTrackerScreen> {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  late Future<List<Transaction>> _transactionsFuture;
  String _searchQuery = '';
  bool _showChart = false;

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  // Método para recarregar a lista de transações
  void _refreshTransactions() {
    setState(() {
      if (_searchQuery.isEmpty) {
        _transactionsFuture = dbHelper.getTransactions();
      } else {
        _transactionsFuture = dbHelper.searchTransactions(_searchQuery);
      }
    });
  }

  // Abre a tela de formulário para adicionar/editar transações
  void _openTransactionForm({Transaction? transaction}) async {
    // Linha 223: Contexto correto para navegação
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransactionFormScreen(transaction: transaction),
      ),
    );
    _refreshTransactions(); // Recarrega após fechar o formulário
  }

  // Confirmação de exclusão
  void _deleteTransaction(int id) async {
    // Linha 235: O contexto é fornecido pelo Widget
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza de que deseja excluir esta transação permanentemente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await dbHelper.deleteTransaction(id);
      _refreshTransactions();
      // Linha 264: Contexto correto para Snackbar
      _showSnackbar('Transação excluída com sucesso!', Colors.red.shade700);
    }
  }

  // Exibe um Snackbar para feedback ao usuário
  void _showSnackbar(String message, Color color) {
    // Uso do contexto correto no ScaffoldMessenger
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Despesas Pessoais'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showChart ? Icons.list : Icons.pie_chart),
            onPressed: () {
              setState(() {
                _showChart = !_showChart;
              });
            },
            tooltip: _showChart ? 'Mostrar Lista' : 'Mostrar Gráfico',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por descrição...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _refreshTransactions();
                });
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Exibe os totais por categoria em um FutureBuilder
          FutureBuilder<Map<String, double>>(
            future: dbHelper.getTotalsByCategory(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: LinearProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink(); // Não mostra se não houver dados
              }
              final totals = snapshot.data!;

              if (_showChart) {
                return ExpenseChart(totals: totals);
              }

              // Card com o total geral
              final totalGeral = totals.values.fold(
                0.0,
                (sum, item) => sum + item,
              );

              return Card(
                margin: const EdgeInsets.all(10),
                elevation: 4,
                child: ListTile(
                  title: const Text(
                    'Total Geral Gasto',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.blueGrey,
                    ),
                  ),
                  trailing: Text(
                    NumberFormat.currency(
                      locale: 'pt_BR',
                      symbol: 'R\$',
                    ).format(totalGeral),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: totalGeral > 0
                          ? Colors.red.shade700
                          : Colors.green,
                    ),
                  ),
                ),
              );
            },
          ),
          // Lista de Transações
          Expanded(
            child: FutureBuilder<List<Transaction>>(
              future: _transactionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'Nenhuma despesa registrada ainda.'
                          : 'Nenhum resultado encontrado para "$_searchQuery".',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return _buildTransactionList(snapshot.data!);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTransactionForm(),
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // Constrói a lista agrupada por data
  Widget _buildTransactionList(List<Transaction> transactions) {
    if (transactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, List<Transaction>> groupedByDate = {};
    for (var transaction in transactions) {
      final dateKey = DateFormat('dd/MM/yyyy').format(transaction.date);
      if (!groupedByDate.containsKey(dateKey)) {
        groupedByDate[dateKey] = [];
      }
      groupedByDate[dateKey]!.add(transaction);
    }

    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('dd/MM/yyyy').parse(a);
        final dateB = DateFormat('dd/MM/yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    return ListView.builder(
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final dateKey = sortedDates[index];
        final dayTransactions = groupedByDate[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 10, bottom: 4),
              child: Text(
                dateKey,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blueGrey,
                ),
              ),
            ),
            ...dayTransactions.map(
              (t) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getCategoryColor(t.category),
                    child: Icon(
                      _getCategoryIcon(t.category),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    t.description,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(t.category),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        NumberFormat.currency(
                          locale: 'pt_BR',
                          symbol: 'R\$',
                        ).format(t.value),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 20,
                          color: Colors.grey,
                        ),
                        onPressed: () => _openTransactionForm(transaction: t),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteTransaction(t.id!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Funções utilitárias para ícones e cores
  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Alimentação':
        return Icons.restaurant;
      case 'Transporte':
        return Icons.directions_bus;
      case 'Lazer':
        return Icons.sports_soccer;
      case 'Saúde':
        return Icons.medical_services;
      case 'Moradia':
        return Icons.home;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Alimentação':
        return Colors.orange;
      case 'Transporte':
        return Colors.blue;
      case 'Lazer':
        return Colors.purple;
      case 'Saúde':
        return Colors.pink;
      case 'Moradia':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

// -----------------------------------------------------------
// 5. Tela de Formulário (TransactionFormScreen)
// -----------------------------------------------------------

class TransactionFormScreen extends StatefulWidget {
  final Transaction? transaction;

  const TransactionFormScreen({super.key, this.transaction});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'Alimentação';

  final List<String> _categories = [
    'Alimentação',
    'Transporte',
    'Lazer',
    'Saúde',
    'Moradia',
    'Outros',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.transaction != null) {
      _descriptionController.text = widget.transaction!.description;
      _valueController.text = widget.transaction!.value.toStringAsFixed(2);
      _selectedDate = widget.transaction!.date;
      _selectedCategory = widget.transaction!.category;
    }
  }

  // Salva a transação no banco de dados
  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final newTransaction = Transaction(
        id: widget.transaction?.id,
        description: _descriptionController.text,
        value: double.parse(_valueController.text.replaceAll(',', '.')),
        date: _selectedDate,
        category: _selectedCategory,
      );

      await DatabaseHelper.instance.insertOrUpdateTransaction(newTransaction);

      // Linha 592: Contexto correto para fechar a tela
      Navigator.of(context).pop();
      // Linha 593: Contexto correto para Snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.transaction == null
                ? 'Transação adicionada com sucesso!'
                : 'Transação editada com sucesso!',
          ),
          backgroundColor: Colors.teal.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Abre o seletor de data
  Future<void> _presentDatePicker() async {
    // Linha 610: Contexto correto para showDatePicker
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.transaction == null ? 'Nova Despesa' : 'Editar Despesa',
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira uma descrição.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor (R\$)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                validator: (value) {
                  if (value == null ||
                      double.tryParse(value.replaceAll(',', '.')) == null) {
                    return 'Por favor, insira um valor válido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Data: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Selecionar Data'),
                    onPressed: _presentDatePicker,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _categories
                    .map(
                      (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                    )
                    .toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedCategory = newValue;
                    });
                  }
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _submitForm,
                icon: Icon(
                  widget.transaction == null ? Icons.save : Icons.update,
                  color: Colors.white,
                ),
                label: Text(
                  widget.transaction == null
                      ? 'Salvar Despesa'
                      : 'Atualizar Despesa',
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 15),
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
} // <-- FECHAMENTO DA CLASSE TransactionFormScreenState

// -----------------------------------------------------------
// 6. Widget do Gráfico de Pizza (Desafio Extra)
// -----------------------------------------------------------

class ExpenseChart extends StatelessWidget {
  final Map<String, double> totals;

  const ExpenseChart({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(
          child: Text(
            "Adicione despesas para ver o gráfico.",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Mapeamento de cores para consistência
    Color _getCategoryColor(String category) {
      switch (category) {
        case 'Alimentação':
          return Colors.orange;
        case 'Transporte':
          return Colors.blue;
        case 'Lazer':
          return Colors.purple;
        case 'Saúde':
          return Colors.pink;
        case 'Moradia':
          return Colors.green;
        default:
          return Colors.grey;
      }
    }

    // Cria as seções do gráfico
    final pieChartSections = totals.entries.toList().asMap().entries.map((
      entry,
    ) {
      final index = entry.key;
      final data = entry.value;
      final category = data.key;
      final percentage =
          (data.value / totals.values.fold(0.0, (sum, item) => sum + item)) *
          100;

      return PieChartSectionData(
        color: _getCategoryColor(category),
        value: data.value,
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 80,
        titleStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
        ),
        badgeWidget: Text(
          category,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _getCategoryColor(category),
          ),
        ),
        badgePositionPercentageOffset: 1.05,
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      height: 300,
      child: PieChart(
        PieChartData(
          sections: pieChartSections,
          sectionsSpace: 2,
          centerSpaceRadius: 40,
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}
