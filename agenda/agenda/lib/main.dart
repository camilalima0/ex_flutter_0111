// Importações necessárias para o Flutter, banco de dados e manipulação de arquivos
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart'
    as p; // <--- CORREÇÃO AQUI: Renomeado o import para 'p'
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

// Constantes do banco de dados
const String tableContact = 'contacts';
const String columnId = '_id';
const String columnFullName = 'fullName';
const String columnCompany = 'company';
const String columnPhone = 'phone';
const String columnEmail = 'email';
const String columnNotes = 'notes';

void main() {
  // Garantir que a inicialização do FlutterBinding esteja completa antes de usar plugins
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgendaApp());
}

/// --------------------------------
/// 1. MODELO DE DADOS (Contact)
/// --------------------------------
class Contact {
  int? id;
  String fullName;
  String company;
  String phone;
  String email;
  String notes;

  Contact({
    this.id,
    required this.fullName,
    required this.company,
    required this.phone,
    required this.email,
    this.notes = '',
  });

  // Converte um Contato para um Map (útil para salvar no banco de dados)
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      columnFullName: fullName,
      columnCompany: company,
      columnPhone: phone,
      columnEmail: email,
      columnNotes: notes,
    };
    if (id != null) {
      map[columnId] = id;
    }
    return map;
  }

  // Converte um Map em um Contato (útil para recuperar do banco de dados)
  Contact.fromMap(Map<String, dynamic> map)
    : id = map[columnId] as int?,
      fullName = map[columnFullName] as String,
      company = map[columnCompany] as String,
      phone = map[columnPhone] as String,
      email = map[columnEmail] as String,
      notes = map[columnNotes] as String;

  // Converte Contato para JSON (útil para exportação)
  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'company': company,
    'phone': phone,
    'email': email,
    'notes': notes,
  };

  // Cria Contato a partir de JSON (útil para importação)
  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      fullName: json['fullName'] as String? ?? '',
      company: json['company'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// --------------------------------
/// 2. ASSISTENTE DE BANCO DE DADOS (DatabaseHelper)
/// --------------------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Obtém o caminho do diretório de documentos do app
    String documentsDirectory = await getDatabasesPath();
    // Usa o prefixo 'p' para o join
    String path = p.join(documentsDirectory, 'professional_contacts.db');

    // Abre o banco de dados. Cria o schema se ainda não existir.
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  void _onCreate(Database db, int version) async {
    // Cria a tabela de contatos
    await db.execute('''
      CREATE TABLE $tableContact (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnFullName TEXT NOT NULL,
        $columnCompany TEXT NOT NULL,
        $columnPhone TEXT NOT NULL,
        $columnEmail TEXT NOT NULL,
        $columnNotes TEXT
      )
    ''');
  }

  // CREATE: Insere um novo contato no banco de dados
  Future<int> insert(Contact contact) async {
    Database db = await database;
    return await db.insert(tableContact, contact.toMap());
  }

  // READ: Obtém todos os contatos, ordenados alfabeticamente pelo nome completo
  Future<List<Contact>> getContacts() async {
    Database db = await database;
    // Query com ordenação alfabética
    List<Map<String, dynamic>> maps = await db.query(
      tableContact,
      orderBy: '$columnFullName ASC',
    );
    return List.generate(maps.length, (i) {
      return Contact.fromMap(maps[i]);
    });
  }

  // UPDATE: Atualiza um contato existente
  Future<int> update(Contact contact) async {
    Database db = await database;
    return await db.update(
      tableContact,
      contact.toMap(),
      where: '$columnId = ?',
      whereArgs: [contact.id],
    );
  }

  // DELETE: Remove um contato pelo ID
  Future<int> delete(int id) async {
    Database db = await database;
    return await db.delete(
      tableContact,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }
}

/// --------------------------------
/// 3. WIDGET PRINCIPAL (AgendaApp)
/// --------------------------------
class AgendaApp extends StatelessWidget {
  const AgendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda Profissional',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
      ),
      home: const ContactListScreen(),
    );
  }
}

/// --------------------------------
/// 4. TELA DE LISTA (ContactListScreen)
/// --------------------------------
class ContactListScreen extends StatefulWidget {
  const ContactListScreen({super.key});

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  late Future<List<Contact>> _contactsFuture;
  final dbHelper = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _refreshContactList();
  }

  // Recarrega a lista de contatos do banco de dados
  void _refreshContactList() {
    setState(() {
      _contactsFuture = dbHelper.getContacts();
    });
  }

  // Navega para a tela de detalhes, esperando por um resultado para atualizar a lista
  void _navigateToDetail([Contact? contact]) async {
    // O 'context' agora referencia o BuildContext e não o do pacote path
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactDetailScreen(contact: contact),
      ),
    );
    _refreshContactList();
  }

  // Exibe um diálogo de confirmação para exclusão
  void _confirmDelete(Contact contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text(
            'Tem certeza que deseja excluir o contato de ${contact.fullName}?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await dbHelper.delete(contact.id!);
                _refreshContactList();
                // Opcional: exibir mensagem de sucesso
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contato excluído com sucesso!'),
                    ),
                  );
                }
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
  }

  // Exibe o diálogo de Importar/Exportar
  void _showImportExportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ImportExportDialog(
        dbHelper: dbHelper,
        onImportSuccess: _refreshContactList,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda Profissional'),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Importar / Exportar Contatos',
            onPressed: _showImportExportDialog,
          ),
        ],
      ),
      body: FutureBuilder<List<Contact>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Erro ao carregar contatos: ${snapshot.error}'),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum contato cadastrado.',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                  ),
                  const Text(
                    'Use o botão "+" para adicionar um novo.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          } else {
            final contacts = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.shade100,
                      child: Text(
                        contact.fullName.isNotEmpty
                            ? contact.fullName[0].toUpperCase()
                            : '?',
                        style: TextStyle(color: Colors.teal.shade800),
                      ),
                    ),
                    title: Text(
                      contact.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${contact.company} | ${contact.phone}'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _navigateToDetail(contact),
                  ),
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToDetail(),
        tooltip: 'Adicionar Contato',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// --------------------------------
/// 5. TELA DE DETALHES/EDIÇÃO (ContactDetailScreen)
/// --------------------------------
class ContactDetailScreen extends StatefulWidget {
  final Contact? contact;

  const ContactDetailScreen({super.key, this.contact});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final dbHelper = DatabaseHelper.instance;

  late TextEditingController _fullNameController;
  late TextEditingController _companyController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _notesController;

  bool get isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    // Inicializa os controladores com os dados do contato ou campos vazios
    _fullNameController = TextEditingController(
      text: widget.contact?.fullName ?? '',
    );
    _companyController = TextEditingController(
      text: widget.contact?.company ?? '',
    );
    _phoneController = TextEditingController(text: widget.contact?.phone ?? '');
    _emailController = TextEditingController(text: widget.contact?.email ?? '');
    _notesController = TextEditingController(text: widget.contact?.notes ?? '');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Função para salvar ou atualizar o contato
  void _saveContact() async {
    if (_formKey.currentState!.validate()) {
      final newContact = Contact(
        id: widget.contact?.id,
        fullName: _fullNameController.text,
        company: _companyController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        notes: _notesController.text,
      );

      try {
        if (isEditing) {
          await dbHelper.update(newContact);
        } else {
          await dbHelper.insert(newContact);
        }

        // Exibir feedback e retornar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Contato ${isEditing ? 'atualizado' : 'salvo'} com sucesso!',
              ),
            ),
          );
          Navigator.pop(context, true); // Retorna com sucesso
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar o contato: $e')),
          );
        }
      }
    }
  }

  // Exclui o contato e retorna
  void _deleteContact() async {
    if (widget.contact?.id != null) {
      // Usar a mesma lógica de confirmação da tela de lista (melhor experiência)
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Confirmar Exclusão'),
            content: Text(
              'Tem certeza que deseja excluir o contato de ${widget.contact!.fullName}?',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  await dbHelper.delete(widget.contact!.id!);
                  if (mounted) {
                    Navigator.of(context).pop(); // Fecha o diálogo
                    Navigator.pop(context, true); // Retorna para a lista
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Contato excluído com sucesso!'),
                      ),
                    );
                  }
                },
                child: const Text('Excluir'),
              ),
            ],
          );
        },
      );
    }
  }

  // Ações rápidas para ligar ou enviar email
  void _launchAction(String action, String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$action para: $value'),
        duration: const Duration(seconds: 1),
      ),
    );
    // Em um app real, aqui você usaria o pacote `url_launcher`
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Contato' : 'Novo Contato'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir Contato',
              onPressed: _deleteContact,
              color: Colors.red.shade100, // Dar um toque de exclusão
            ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Salvar Contato',
            onPressed: _saveContact,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Campo Nome Completo
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Nome Completo*',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  hintText: 'Ex: João da Silva',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'O nome completo é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Campo Empresa
              TextFormField(
                controller: _companyController,
                decoration: const InputDecoration(
                  labelText: 'Empresa',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  hintText: 'Ex: TechSolutions Ltda',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'A empresa é obrigatória.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Campo Telefone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefone*',
                  prefixIcon: const Icon(Icons.phone),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  hintText: 'Ex: (11) 98765-4321',
                  // Ícone de ação (Ligar)
                  suffixIcon: isEditing
                      ? IconButton(
                          icon: const Icon(Icons.call, color: Colors.teal),
                          onPressed: () =>
                              _launchAction('Ligando', _phoneController.text),
                        )
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'O telefone é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Campo E-mail
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail*',
                  prefixIcon: const Icon(Icons.email),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  hintText: 'Ex: joao.silva@empresa.com',
                  // Ícone de ação (Enviar Email)
                  suffixIcon: isEditing
                      ? IconButton(
                          icon: const Icon(Icons.mail, color: Colors.teal),
                          onPressed: () => _launchAction(
                            'Enviando e-mail',
                            _emailController.text,
                          ),
                        )
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty || !value.contains('@')) {
                    return 'E-mail inválido ou obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Campo Observações
              TextFormField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 60),
                    child: Icon(Icons.edit_note),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              // Botão Salvar (redundante, mas bom para UX)
              Center(
                child: ElevatedButton.icon(
                  onPressed: _saveContact,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    isEditing ? 'Atualizar Contato' : 'Salvar Novo Contato',
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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

/// --------------------------------
/// 6. DIÁLOGO DE IMPORTAÇÃO/EXPORTAÇÃO (Extra Challenge)
/// --------------------------------
class ImportExportDialog extends StatefulWidget {
  final DatabaseHelper dbHelper;
  final VoidCallback onImportSuccess;

  const ImportExportDialog({
    super.key,
    required this.dbHelper,
    required this.onImportSuccess,
  });

  @override
  State<ImportExportDialog> createState() => _ImportExportDialogState();
}

class _ImportExportDialogState extends State<ImportExportDialog> {
  String _statusMessage = 'Selecione uma opção.';
  bool _isLoading = false;

  // Obtém o caminho do diretório de documentos do app
  Future<String> _getAppDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // EXPORTAÇÃO
  Future<void> _exportContacts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Exportando contatos...';
    });

    try {
      final contacts = await widget.dbHelper.getContacts();
      if (contacts.isEmpty) {
        setState(() {
          _statusMessage = 'Não há contatos para exportar.';
          _isLoading = false;
        });
        return;
      }

      // Converte a lista de contatos para JSON
      final List<Map<String, dynamic>> jsonList = contacts
          .map((c) => c.toJson())
          .toList();
      final String jsonString = jsonEncode(jsonList);

      // Salva o arquivo no diretório do app
      final appDirPath = await _getAppDirectoryPath();
      // Usa o prefixo 'p' para o join
      final filePath = p.join(appDirPath, 'agenda_contatos_profissionais.json');
      final file = File(filePath);
      await file.writeAsString(jsonString);

      // Compartilha o arquivo
      await Share.shareXFiles([
        XFile(filePath),
      ], subject: 'Contatos Profissionais Exportados');

      setState(() {
        _statusMessage =
            'Exportado com sucesso para o arquivo e pronto para compartilhar!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Erro na exportação: $e';
        _isLoading = false;
      });
    }
  }

  // IMPORTAÇÃO
  Future<void> _importContacts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Abrindo seletor de arquivos...';
    });

    try {
      // 1. Abre o seletor de arquivos
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _statusMessage = 'Importação cancelada.';
          _isLoading = false;
        });
        return;
      }

      final file = File(result.files.single.path!);
      final String jsonString = await file.readAsString();

      // 2. Processa o JSON
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final List<Contact> newContacts = jsonList.map((json) {
        return Contact.fromJson(json as Map<String, dynamic>);
      }).toList();

      if (newContacts.isEmpty) {
        setState(() {
          _statusMessage = 'O arquivo JSON não contém contatos válidos.';
          _isLoading = false;
        });
        return;
      }

      // 3. Insere no banco de dados
      int insertedCount = 0;
      for (var contact in newContacts) {
        // Zera o ID para garantir que seja uma nova inserção
        contact.id = null;
        await widget.dbHelper.insert(contact);
        insertedCount++;
      }

      // 4. Conclui
      widget.onImportSuccess(); // Notifica a tela de lista para atualizar
      setState(() {
        _statusMessage =
            'Sucesso! $insertedCount contatos importados e salvos.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Erro na importação: Arquivo inválido ou $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usar SingleChildScrollView em BottomSheet para evitar overflow de teclado (caso fosse necessário)
    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Importar/Exportar Contatos (JSON)',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const Divider(height: 30),
          // Botão Exportar
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportContacts,
            icon: const Icon(Icons.share),
            label: const Text('Exportar e Compartilhar JSON'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.teal.shade50,
              foregroundColor: Colors.teal.shade800,
            ),
          ),
          const SizedBox(height: 12),
          // Botão Importar
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _importContacts,
            icon: const Icon(Icons.file_upload),
            label: const Text('Importar Contatos de JSON'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          // Status/Feedback
          Center(
            child: _isLoading
                ? const CircularProgressIndicator()
                : Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.contains('Erro')
                          ? Colors.red
                          : Colors.black54,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
