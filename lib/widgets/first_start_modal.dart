import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/specs_provider.dart';

class FirstStartModal extends StatefulWidget {
  final VoidCallback onCompleted;

  const FirstStartModal({super.key, required this.onCompleted});

  @override
  State<FirstStartModal> createState() => _FirstStartModalState();
}

class _FirstStartModalState extends State<FirstStartModal> {
  String _selectedStore = 'none';
  final TextEditingController _pricePrimaryController = TextEditingController();
  final TextEditingController _priceSecondaryController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController(text: 'demo');

  void _save() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    
    final specsToSave = {
      'store': _selectedStore,
      'pricePrimary': _pricePrimaryController.text.trim(),
      'priceSecondary': _priceSecondaryController.text.trim(),
      'sku': _skuController.text.trim().replaceAll(RegExp(r'\D'), ''),
      'adminPassword': _passwordController.text.trim().isEmpty ? 'demo' : _passwordController.text.trim(),
      'firstStartCompleted': true,
    };

    provider.saveCustom(specsToSave);
    widget.onCompleted();
  }

  @override
  void dispose() {
    _pricePrimaryController.dispose();
    _priceSecondaryController.dispose();
    _skuController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve theme for the temporary selection to show color feedback in preview
    var tempStore = RetailStore.none;
    switch (_selectedStore) {
      case 'falabella': tempStore = RetailStore.falabella; break;
      case 'paris': tempStore = RetailStore.paris; break;
      case 'ripley': tempStore = RetailStore.ripley; break;
    }
    final theme = RetailTheme.of(tempStore);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 550,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: theme.primary.withValues(alpha: 0.08),
                  blurRadius: 50,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.settings_suggest, color: theme.primary, size: 28),
                    ),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configuración Inicial',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Personalice los parámetros comerciales de la vitrina',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 40),
                
                // Retail Selection
                const Text(
                  '1. Distribuidor / Retail',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StoreOption(
                      label: 'Otras (Defecto)',
                      value: 'none',
                      selectedValue: _selectedStore,
                      activeColor: const Color(0xFF00F2AA),
                      onChanged: (val) => setState(() => _selectedStore = val),
                    ),
                    const SizedBox(width: 10),
                    _StoreOption(
                      label: 'Falabella',
                      value: 'falabella',
                      selectedValue: _selectedStore,
                      activeColor: const Color(0xFFB9D40D),
                      onChanged: (val) => setState(() => _selectedStore = val),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StoreOption(
                      label: 'Paris',
                      value: 'paris',
                      selectedValue: _selectedStore,
                      activeColor: const Color(0xFF00D1FF),
                      onChanged: (val) => setState(() => _selectedStore = val),
                    ),
                    const SizedBox(width: 10),
                    _StoreOption(
                      label: 'Ripley',
                      value: 'ripley',
                      selectedValue: _selectedStore,
                      activeColor: const Color(0xFFAF47FF),
                      onChanged: (val) => setState(() => _selectedStore = val),
                    ),
                  ],
                ),
                
                const SizedBox(height: 30),

                // Pricing
                const Text(
                  '2. Información Comercial',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInput(
                        label: 'Precio Tarjeta',
                        controller: _pricePrimaryController,
                        placeholder: 'Ej: \$899.990',
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildInput(
                        label: 'Precio Todo Pago',
                        controller: _priceSecondaryController,
                        placeholder: 'Ej: \$949.990',
                        theme: theme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildInput(
                  label: 'SKU del Producto',
                  controller: _skuController,
                  placeholder: 'Ej: 8847382',
                  onlyDigits: true,
                  theme: theme,
                ),

                const SizedBox(height: 30),

                // Security Password
                const Text(
                  '3. Seguridad',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                _buildInput(
                  label: 'Código de Acceso del Administrador',
                  controller: _passwordController,
                  placeholder: 'Por defecto: demo',
                  theme: theme,
                ),

                const SizedBox(height: 40),

                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Guardar y Activar Vitrina',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required RetailTheme theme,
    bool onlyDigits = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
        ),
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
          onChanged: (val) {
            if (onlyDigits) {
              final clean = val.replaceAll(RegExp(r'\D'), '');
              if (clean != val) {
                controller.value = controller.value.copyWith(
                  text: clean,
                  selection: TextSelection.collapsed(offset: clean.length),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

class _StoreOption extends StatelessWidget {
  final String label;
  final String value;
  final String selectedValue;
  final Color activeColor;
  final ValueChanged<String> onChanged;

  const _StoreOption({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedValue == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? activeColor : Colors.grey,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeColor,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
