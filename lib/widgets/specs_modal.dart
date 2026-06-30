import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/specs_provider.dart';

class SpecsModal extends StatelessWidget {
  final VoidCallback onClose;

  const SpecsModal({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SpecsProvider>(context);
    final theme = RetailTheme.of(provider.store);
    final specs = provider.currentSpecs;

    final infoItems = [
      _SpecItem(label: 'Marca y Modelo', value: '${specs['brand']} ${specs['model']}'),
      _SpecItem(label: 'Procesador', value: '${specs['processor']} (${specs['cores']} Cores / ${specs['threads']} Threads)'),
      _SpecItem(label: 'Generación', value: '${specs['gen']}'),
      _SpecItem(label: 'Gráficos (GPU)', value: '${specs['gpu']}'),
      _SpecItem(label: 'Memoria RAM', value: '${specs['ram']} (${specs['ramType']})'),
      _SpecItem(label: 'Almacenamiento', value: '${specs['storage']}'),
      _SpecItem(label: 'Pantalla', value: '${specs['display']}'),
      _SpecItem(label: 'Sistema Operativo', value: '${specs['os']}'),
      if (specs['sku'] != null && specs['sku'].toString().isNotEmpty)
        _SpecItem(label: 'SKU del Retail', value: '${specs['sku']}'),
    ];

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      body: Center(
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: theme.primary.withValues(alpha: 0.05),
                blurRadius: 40,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Especificaciones Detalladas',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: onClose,
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 25),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: infoItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 15),
                  itemBuilder: (context, index) {
                    final item = infoItems[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            color: theme.primary.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Cerrar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecItem {
  final String label;
  final String value;
  _SpecItem({required this.label, required this.value});
}
