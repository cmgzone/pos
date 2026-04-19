import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../data/category_repository.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    _categories = await CategoryRepository.getAll();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Category Management'),
        actions: [
          FilledButton.icon(
            onPressed: () => _showCategoryDialog(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Category'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No categories yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => _showCategoryDialog(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Create your first category'),
                  ),
                ],
              ),
            )
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final colorHex = category['color'] as String?;
                    final color = colorHex != null
                        ? Color(int.parse(colorHex.replaceFirst('#', '0xFF')))
                        : AppColors.primary;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              CategoryIconUtils.iconFor(
                                category['name'] as String?,
                              ),
                              color: color,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category['name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${(category['id'] as String).substring(0, 8)}...',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Color indicator
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white24,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => _showCategoryDialog(category),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: AppColors.error,
                            ),
                            onPressed: () => _confirmDelete(category),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  void _showCategoryDialog(Map<String, dynamic>? existing) {
    final nameController = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final colorController = TextEditingController(
      text: existing?['color'] as String? ?? '#6B4EE6',
    );
    final isEditing = existing != null;

    final presetColors = [
      '#6B4EE6',
      '#00E5FF',
      '#32D74B',
      '#FF9F0A',
      '#FF453A',
      '#FF6B9D',
      '#FFD60A',
      '#5E5CE6',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(isEditing ? 'Edit Category' : 'New Category'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Name',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Electronics',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Color',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: presetColors.map((hex) {
                    final isSelected = colorController.text == hex;
                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => colorController.text = hex),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse(hex.replaceFirst('#', '0xFF')),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Color(
                                      int.parse(hex.replaceFirst('#', '0xFF')),
                                    ).withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                if (isEditing) {
                  await CategoryRepository.update(existing['id'] as String, {
                    'name': nameController.text.trim(),
                    'color': colorController.text,
                  });
                } else {
                  await CategoryRepository.create(
                    name: nameController.text.trim(),
                    color: colorController.text,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadCategories();
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(isEditing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Category'),
        content: Text(
          'Delete "${category['name']}"? Products in this category won\'t be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await CategoryRepository.delete(category['id'] as String);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadCategories();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
