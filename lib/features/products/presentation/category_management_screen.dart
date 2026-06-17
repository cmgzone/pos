import 'package:flutter/material.dart';
import 'package:pos_app/features/app/app_shell.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../../core/utils/error_messages.dart';
import '../../training/widgets/training_anchor.dart';
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
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Text('Category Management'),
        actions: [
          TrainingAnchor(
            id: 'categories.add',
            child: FilledButton.icon(
              onPressed: () => _showCategoryDialog(null),
              icon: Icon(Icons.add, size: 18),
              label: Text('Add Category'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
          SizedBox(width: 16),
        ],
      ),
      body: TrainingAnchor(
        id: 'categories.list',
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _categories.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No categories yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _showCategoryDialog(null),
                      icon: Icon(Icons.add),
                      label: Text('Create your first category'),
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
                    separatorBuilder: (_, _) => SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final color = _parseColor(category['color'] as String?);
                      final categoryId = (category['id'] as String?) ?? '';
                      final categoryName = (category['name'] as String?) ?? '';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
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
                                CategoryIconUtils.iconFor(categoryName),
                                color: color,
                                size: 22,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    categoryName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'ID: ${categoryId.length >= 8 ? categoryId.substring(0, 8) : categoryId}...',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            SizedBox(width: 16),
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () => _showCategoryDialog(category),
                            ),
                            IconButton(
                              icon: Icon(
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
      ),
    );
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.trim().isEmpty) return AppColors.primary;
    final normalized = colorHex.trim().toUpperCase();
    // Accept 3, 6, or 8 digit hex with optional leading #
    final hex = normalized.replaceFirst('#', '');
    if (!RegExp(r'^[0-9A-F]{3}([0-9A-F]{3})?([0-9A-F]{2})?$').hasMatch(hex)) {
      return AppColors.primary;
    }
    try {
      String fullHex;
      if (hex.length == 3) {
        fullHex = 'FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
      } else if (hex.length == 6) {
        fullHex = 'FF$hex';
      } else {
        fullHex = hex;
      }
      return Color(int.parse(fullHex, radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
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
                Text(
                  'Name',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'e.g. Electronics',
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Color',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 12),
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
                          color: _parseColor(hex),
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
                                    color: _parseColor(hex).withValues(alpha: 0.5),
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
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                if (isEditing) {
                  final id = existing['id'] as String?;
                  if (id == null || id.isEmpty) return;
                  await CategoryRepository.update(id, {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Category'),
        content: Text(
          'Delete "${category['name'] as String? ?? ''}"? Products in this category won\'t be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final id = category['id'] as String?;
              if (id == null || id.isEmpty) return;
              try {
                await CategoryRepository.delete(id);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  await _loadCategories();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Category deleted'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (error) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        AppErrorMessage.withContext(
                          error,
                          prefix: 'Could not delete category.',
                          fallback:
                              'Could not delete this category. Please try again.',
                        ),
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}
