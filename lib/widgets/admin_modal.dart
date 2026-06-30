import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../providers/specs_provider.dart';

class AdminModal extends StatefulWidget {
  final VoidCallback onClose;

  const AdminModal({super.key, required this.onClose});

  @override
  State<AdminModal> createState() => _AdminModalState();
}

class _AdminModalState extends State<AdminModal> {
  String _activeTab = 'hardware';
  late final Map<String, dynamic> _editableSpecs;
  final _formKey = GlobalKey<FormState>();

  // Catálogo estático de videos del sistema
  static const List<Map<String, String>> systemVideosCatalog = [
    {'name': '🏠 Original Asus AI (Home)', 'path': '__ASUS_LANDING__'},
    {'name': '🏢 Original Genérico Win 11 (Home)', 'path': '__GENERIC_LANDING__'},
    {'name': '🔥 Original Asus Durabilidad (Promo)', 'path': '__ASUS_PROMO__'},
    {'name': '🪟 Original Genérico (Promo) Move to Win 11', 'path': '__GENERIC_PROMO__'},
    {'name': '🎮 Xbox Game Pass (Gaming)', 'path': '__GAMING_XBOX__'},
    {'name': '💻 Windows: Home of Gaming', 'path': '__WINDOWS_GAMING__'},
    {'name': '✨ ROG Calidad y Durabilidad', 'path': '__QUALITY_DURABILITY__'},
    {'name': '🛡️ TUF Gaming: Durabilidad', 'path': '__TUF_DURABILITY__'},
    {'name': '✅ Asus Garantía Perfecta', 'path': '__ASUS_WARRANTY__'},
  ];

  // Controladores de texto para la pestaña de Hardware
  late final Map<String, TextEditingController> _controllers;

  // Controladores adicionales
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _pricePrimaryController = TextEditingController();
  final TextEditingController _priceSecondaryController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    
    // Clonar las especificaciones activas para edición
    _editableSpecs = Map<String, dynamic>.from(provider.currentSpecs);

    // Inicializar slots de videos de inactividad
    final List<dynamic> baseSlots = _editableSpecs['customVideoPaths'] ?? [];
    final List<Map<String, String>> slots = [];
    for (var i = 0; i < 3; i++) {
      if (i < baseSlots.length) {
        slots.add({
          'name': (baseSlots[i]['name'] ?? '').toString(),
          'path': (baseSlots[i]['path'] ?? '').toString(),
        });
      } else {
        slots.add({'name': '', 'path': ''});
      }
    }
    _editableSpecs['customVideoPaths'] = slots;

    // Inicializar controladores de Hardware
    _controllers = {
      'model': TextEditingController(text: _editableSpecs['model'] ?? ''),
      'processor': TextEditingController(text: _editableSpecs['processor'] ?? ''),
      'gen': TextEditingController(text: _editableSpecs['gen'] ?? ''),
      'ram': TextEditingController(text: _editableSpecs['ram'] ?? ''),
      'ramType': TextEditingController(text: _editableSpecs['ramType'] ?? ''),
      'storage': TextEditingController(text: _editableSpecs['storage'] ?? ''),
      'gpu': TextEditingController(text: _editableSpecs['gpu'] ?? ''),
      'display': TextEditingController(text: _editableSpecs['display'] ?? ''),
      'os': TextEditingController(text: _editableSpecs['os'] ?? ''),
    };

    // Inicializar otros controladores
    _skuController.text = _editableSpecs['sku'] ?? '';
    _pricePrimaryController.text = _editableSpecs['pricePrimary'] ?? '';
    _priceSecondaryController.text = _editableSpecs['priceSecondary'] ?? '';
    _passwordController.text = _editableSpecs['adminPassword'] ?? '';
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _skuController.dispose();
    _pricePrimaryController.dispose();
    _priceSecondaryController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _restoreField(String field) {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    final autoValue = provider.autoDetectedSpecs[field] ?? '';
    setState(() {
      _controllers[field]?.text = autoValue.toString();
      _editableSpecs[field] = autoValue;
    });
  }

  String _getVideoDisplayName(String path) {
    if (path.isEmpty) return 'Sin video';
    final match = systemVideosCatalog.firstWhere(
      (element) => element['path'] == path,
      orElse: () => {'name': '', 'path': ''},
    );
    if (match['name']!.isNotEmpty) return match['name']!;
    
    // Si no es interno, es de la bóveda: mostrar el nombre del archivo
    return p.basenameWithoutExtension(path).replaceAll(RegExp(r'^\d{10,}_'), '');
  }

  // Sube un video local del PC del administrador
  Future<void> _pickAndSaveVideo(String type, {int? slotIndex}) async {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    
    // Desactivar siempre al frente temporalmente para permitir ver el cuadro de diálogo de archivos de Windows
    provider.windowService.setAlwaysOnTop(false);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowedExtensions: ['mp4'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final savedPath = await provider.vaultService.saveCustomVideo(filePath);
        
        if (savedPath != null) {
          // Recargar videos en el provider
          await provider.loadSpecs();
          
          setState(() {
            final fileName = p.basenameWithoutExtension(savedPath).replaceAll(RegExp(r'^\d{10,}_'), '');
            if (type == 'landing') {
              _editableSpecs['customLandingVideoPath'] = savedPath;
              _editableSpecs['customLandingVideoName'] = fileName;
              _editableSpecs['landingVideoType'] = 'custom';
            } else if (type == 'inactivity' && slotIndex != null) {
              _editableSpecs['customVideoPaths'][slotIndex]['path'] = savedPath;
              _editableSpecs['customVideoPaths'][slotIndex]['name'] = fileName;
              _editableSpecs['videoType'] = 'custom';
            }
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video guardado correctamente en la Bóveda ✓')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      provider.windowService.setAlwaysOnTop(true);
    }
  }

  // Elimina físicamente un video de la bóveda
  Future<void> _deleteSavedVideo(String path) async {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('¿Eliminar video?', style: TextStyle(color: Colors.white)),
        content: Text('¿Estás seguro de que quieres eliminar físicamente este video de la bóveda?\nSe restaurarán los fallbacks en caso de estar en uso.', 
            style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await provider.vaultService.deleteCustomVideo(path);
        
        // Sucesión y fallbacks
        setState(() {
          if (_editableSpecs['customLandingVideoPath'] == path) {
            final isAsus = provider.isAsus;
            _editableSpecs['customLandingVideoPath'] = isAsus ? '__ASUS_LANDING__' : '__GENERIC_LANDING__';
            _editableSpecs['customLandingVideoName'] = isAsus ? 'Original Asus AI (Home)' : 'Original Genérico Win 11 (Home)';
            _editableSpecs['landingVideoType'] = 'default';
          }

          final List<dynamic> slots = _editableSpecs['customVideoPaths'];
          for (var slot in slots) {
            if (slot['path'] == path) {
              final isAsus = provider.isAsus;
              slot['path'] = isAsus ? '__ASUS_PROMO__' : '__GENERIC_PROMO__';
              slot['name'] = isAsus ? 'Original Asus Durabilidad (Promo)' : 'Original Genérico (Promo) Move to Win 11';
            }
          }
        });

        await provider.loadSpecs();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video eliminado físicamente ✓')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _removeVideoFromSlot(int index) {
    // Al menos un slot debe tener video activo
    final activeCount = (_editableSpecs['customVideoPaths'] as List).where((s) => (s['path'] as String).isNotEmpty).length;
    if (activeCount <= 1 && (_editableSpecs['customVideoPaths'][index]['path'] as String).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Siempre debe haber al menos un video de inactividad activo.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _editableSpecs['customVideoPaths'][index]['path'] = '';
      _editableSpecs['customVideoPaths'][index]['name'] = '';
    });
  }

  void _clearPrices() {
    setState(() {
      _pricePrimaryController.clear();
      _priceSecondaryController.clear();
      _editableSpecs['pricePrimary'] = '';
      _editableSpecs['priceSecondary'] = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Precios limpiados ✓')),
    );
  }

  void _save() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);

    // 1. Validar que la inactividad tenga al menos un video
    final activeScreensavers = (_editableSpecs['customVideoPaths'] as List).where((s) => (s['path'] as String).isNotEmpty).length;
    if (activeScreensavers == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Debe asignar al menos un video de inactividad.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    // 2. Volcar controladores de texto a specs
    for (var key in _controllers.keys) {
      _editableSpecs[key] = _controllers[key]?.text.trim() ?? '';
    }
    _editableSpecs['sku'] = _skuController.text.trim().replaceAll(RegExp(r'\D'), '');
    _editableSpecs['pricePrimary'] = _pricePrimaryController.text.trim();
    _editableSpecs['priceSecondary'] = _priceSecondaryController.text.trim();
    _editableSpecs['adminPassword'] = _passwordController.text.trim().isEmpty ? 'demo' : _passwordController.text.trim();

    provider.saveCustom(_editableSpecs);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración guardada exitosamente ✓')),
    );
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SpecsProvider>(context);
    final theme = RetailTheme.of(provider.store);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      body: Center(
        child: Container(
          width: 800,
          height: 650,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(left: 30, right: 30, top: 35, bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Personalizar Zenit',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'v1.8.0',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Desarrollado por Juan Marchant',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // Tabs Menu
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Row(
                  children: [
                    _buildTabBtn('hardware', 'Hardware'),
                    _buildTabBtn('visual', 'Visual (Videos y Fondos)'),
                    _buildTabBtn('tienda', 'Tienda y Seguridad'),
                  ],
                ),
              ),

              // Body scroll
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: _buildTabContent(theme, provider),
                    ),
                  ),
                ),
              ),

              // Footer Actions
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF151515),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Guardar Cambios',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 15),
                    TextButton(
                      onPressed: widget.onClose,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBtn(String tabKey, String label) {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    final theme = RetailTheme.of(provider.store);
    final isActive = _activeTab == tabKey;

    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Container(
        margin: const EdgeInsets.only(right: 15),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? theme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey,
            fontSize: 14,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(RetailTheme theme, SpecsProvider provider) {
    if (_activeTab == 'hardware') {
      return Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 15,
            crossAxisSpacing: 20,
            childAspectRatio: 2.8,
            children: [
              _buildHardwareField('brand', 'Marca (Auto-detectada)', disabled: true, theme: theme),
              _buildHardwareField('model', 'Modelo', theme: theme),
              _buildHardwareField('processor', 'Procesador', theme: theme),
              _buildHardwareField('gen', 'Generación / Tag', theme: theme),
              _buildHardwareField('ram', 'RAM (Capacidad)', theme: theme),
              _buildHardwareField('ramType', 'Tipo RAM (DDR4/5)', theme: theme),
              _buildHardwareField('storage', 'Almacenamiento', theme: theme),
              _buildHardwareField('gpu', 'Gráficos (GPU)', theme: theme),
              _buildHardwareField('display', 'Resolución de Pantalla', theme: theme),
              _buildHardwareField('os', 'Sistema Operativo', theme: theme),
            ],
          ),
        ],
      );
    }

    if (_activeTab == 'visual') {
      final isAsusBrand = (provider.currentSpecs['brand'] ?? '').toString().toLowerCase().contains('asus') ||
          (provider.currentSpecs['model'] ?? '').toString().toLowerCase().contains('asus');
      
      final List<dynamic> inactivitySlots = _editableSpecs['customVideoPaths'];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Retail store select & Checkbox
          const Text(
            'Marca y Entorno Relacional',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Retail / Tienda', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: const Color(0xFF1E1E1E),
                          value: _editableSpecs['store'] ?? 'none',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: (val) {
                            setState(() {
                              _editableSpecs['store'] = val;
                            });
                          },
                          items: const [
                            DropdownMenuItem(value: 'none', child: Text('Otras')),
                            DropdownMenuItem(value: 'falabella', child: Text('Falabella')),
                            DropdownMenuItem(value: 'paris', child: Text('Paris')),
                            DropdownMenuItem(value: 'ripley', child: Text('Ripley')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isAsusBrand) const SizedBox(width: 30),
              if (isAsusBrand)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Configuración de Pantalla', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        value: _editableSpecs['showAsusWarrantyTicker'] ?? false,
                        activeColor: theme.primary,
                        checkColor: Colors.black,
                        title: const Text('Mostrar publicidad garantía perfecta ASUS', style: TextStyle(color: Colors.white, fontSize: 13)),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setState(() {
                            _editableSpecs['showAsusWarrantyTicker'] = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
          
          const Divider(color: Colors.white10, height: 40),

          // Video Home
          const Text(
            'Video Home (Visualización en App)',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          _buildVideoSelector(
            type: 'landing',
            currentPath: _editableSpecs['customLandingVideoPath'] ?? '',
            theme: theme,
          ),

          const Divider(color: Colors.white10, height: 40),

          // Videos de Inactividad (Screensaver)
          const Text(
            'Videos de Inactividad (Ad Múltiple)',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: inactivitySlots.length,
            separatorBuilder: (_, _) => const SizedBox(height: 15),
            itemBuilder: (context, index) {
              final slot = inactivitySlots[index];
              return Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('SLOT DE VIDEO ${index + 1}', style: TextStyle(color: theme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                        if ((slot['path'] as String).isNotEmpty)
                          TextButton(
                            onPressed: () => _removeVideoFromSlot(index),
                            style: TextButton.styleFrom(foregroundColor: Colors.redAccent, padding: EdgeInsets.zero),
                            child: const Text('Limpiar Slot (X)', style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildVideoSelector(
                      type: 'inactivity',
                      slotIndex: index,
                      currentPath: slot['path'] ?? '',
                      theme: theme,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    }

    if (_activeTab == 'tienda') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Información de Precios y Comercialización',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Columna Izquierda: Inputs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextFormInput(
                      label: 'SKU del Producto',
                      controller: _skuController,
                      placeholder: 'Ej: 9948283',
                      onlyDigits: true,
                      theme: theme,
                    ),
                    const SizedBox(height: 15),
                    _buildTextFormInput(
                      label: 'Precio Tarjeta',
                      controller: _pricePrimaryController,
                      placeholder: 'Ej: \$899.990',
                      theme: theme,
                    ),
                    const SizedBox(height: 15),
                    _buildTextFormInput(
                      label: 'Precio Todo Medio',
                      controller: _priceSecondaryController,
                      placeholder: 'Ej: \$959.990',
                      theme: theme,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _clearPrices,
                      icon: const Icon(Icons.cleaning_services, size: 16),
                      label: const Text('Limpiar Precios'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              // Columna Derecha: Estado de Tienda (Badges)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Etiqueta / Estado de Tienda', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 12),
                    _buildBadgeRadio('none', 'Ninguno (Normal)', theme),
                    _buildBadgeRadio('delivery', 'Solo Despacho', theme),
                    _buildBadgeRadio('no-stock', 'Sin Stock', theme),
                    _buildBadgeRadio('last-unit', 'Última unidad', theme),
                  ],
                ),
              ),
            ],
          ),

          const Divider(color: Colors.white10, height: 40),

          // Security password update
          const Text(
            'Seguridad y Acceso',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          _buildTextFormInput(
            label: 'Código de Acceso (Admin)',
            controller: _passwordController,
            placeholder: 'demo',
            theme: theme,
          ),
          const SizedBox(height: 6),
          const Text(
            'Este código protege el panel de configuración de Zenit y te permite salir del modo kiosko.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      );
    }

    return const SizedBox();
  }

  Widget _buildHardwareField(String fieldKey, String label, {bool disabled = false, required RetailTheme theme}) {
    final controller = _controllers[fieldKey];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !disabled,
                maxLength: 80,
                buildCounter: (context, {required currentLength, required isFocused, required maxLength}) => null, // Ocultar contador largo
                style: TextStyle(color: disabled ? Colors.grey : Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.2),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
                  ),
                ),
              ),
            ),
            if (!disabled) const SizedBox(width: 8),
            if (!disabled)
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                color: theme.primary,
                tooltip: 'Restaurar auto-detectado',
                onPressed: () => _restoreField(fieldKey),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextFormInput({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required RetailTheme theme,
    bool onlyDigits = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: onlyDigits ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: theme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeRadio(String value, String label, RetailTheme theme) {
    final active = (_editableSpecs['storeBadge'] ?? 'none') == value;
    return GestureDetector(
      onTap: () => setState(() => _editableSpecs['storeBadge'] = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? theme.primary : Colors.grey,
                  width: 2,
                ),
              ),
              child: active
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSelector({
    required String type,
    int? slotIndex,
    required String currentPath,
    required RetailTheme theme,
  }) {
    // Filtrar los videos del catálogo para ASUS si la marca corresponde
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    final isAsusBrand = provider.isAsus;
    
    final filteredCatalog = systemVideosCatalog.where((v) {
      const asusVideos = ['__ASUS_PROMO__', '__ASUS_LANDING__', '__QUALITY_DURABILITY__', '__TUF_DURABILITY__', '__ASUS_WARRANTY__'];
      if (asusVideos.contains(v['path'])) {
        return isAsusBrand;
      }
      return true;
    }).toList();

    final isSystemVideo = systemVideosCatalog.any((v) => v['path'] == currentPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Opción 1: Dropdown de internos / bóveda
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Opción 1: Internos o Bóveda', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E1E1E),
                        value: currentPath.isEmpty ? null : currentPath,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            if (type == 'landing') {
                              _editableSpecs['customLandingVideoPath'] = val;
                              _editableSpecs['customLandingVideoName'] = _getVideoDisplayName(val);
                              _editableSpecs['landingVideoType'] = systemVideosCatalog.any((v) => v['path'] == val) ? 'default' : 'custom';
                            } else if (type == 'inactivity' && slotIndex != null) {
                              _editableSpecs['customVideoPaths'][slotIndex]['path'] = val;
                              _editableSpecs['customVideoPaths'][slotIndex]['name'] = _getVideoDisplayName(val);
                              _editableSpecs['videoType'] = 'custom';
                            }
                          });
                        },
                        items: [
                          DropdownMenuItem<String>(
                            enabled: false,
                            child: Text('Videos del Sistema', style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                          ...filteredCatalog.map(
                            (v) => DropdownMenuItem<String>(
                              value: v['path'],
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(v['name']!),
                              ),
                            ),
                          ),
                          if (provider.savedVideos.isNotEmpty) ...[
                            DropdownMenuItem<String>(
                              enabled: false,
                              child: Text('Bóveda (Subidos)', style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                            ...provider.savedVideos.map(
                              (v) => DropdownMenuItem<String>(
                                value: v.path,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Text(v.name),
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            
            // Opción 2: Subir archivo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Opción 2: Desde PC Local', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    onPressed: () => _pickAndSaveVideo(type, slotIndex: slotIndex),
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Subir Nuevo Video', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Preview del archivo seleccionado y eliminación física
        if (currentPath.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSystemVideo ? 'Asset interno del sistema' : 'Archivo de Bóveda subido',
                        style: TextStyle(color: theme.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _getVideoDisplayName(currentPath),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (!isSystemVideo)
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                    tooltip: 'Eliminar físicamente de la Bóveda',
                    onPressed: () => _deleteSavedVideo(currentPath),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
