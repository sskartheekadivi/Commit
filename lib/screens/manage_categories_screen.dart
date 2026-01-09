import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:commit/database/database.dart';
import 'package:commit/providers/providers.dart';

class ManageCategoriesScreen extends ConsumerWidget {
  const ManageCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
      ),
      body: categoriesAsync.when(
        data: (categories) => ReorderableListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return ListTile(
              key: ValueKey(category.id),
              title: Text(category.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showAddEditCategoryDialog(context, ref, category: category),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _showDeleteCategoryDialog(context, ref, category),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                ],
              ),
            );
          },
          onReorder: (oldIndex, newIndex) {
            if (oldIndex < newIndex) {
              newIndex -= 1;
            }
            final updatedCategories = List<Category>.from(categories);
            final item = updatedCategories.removeAt(oldIndex);
            updatedCategories.insert(newIndex, item);
            ref.read(habitRepositoryProvider).updateCategoryOrder(updatedCategories);
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditCategoryDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddEditCategoryDialog(BuildContext context, WidgetRef ref, {Category? category}) {
    final isEditing = category != null;
    final TextEditingController nameController = TextEditingController(text: category?.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Category' : 'Add Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Category Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final repo = ref.read(habitRepositoryProvider);
                try {
                  if (isEditing) {
                    await repo.updateCategory(category.copyWith(name: name));
                  } else {
                    await repo.createCategory(name);
                  }
                  Navigator.of(context).pop();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCategoryDialog(BuildContext context, WidgetRef ref, Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: const Text('What would you like to do with the habits in this category?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(habitRepositoryProvider).deleteCategory(category.id, false);
              Navigator.of(context).pop();
            },
            child: const Text('Keep Habits'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(habitRepositoryProvider).deleteCategory(category.id, true);
              Navigator.of(context).pop();
            },
            child: const Text('Delete Habits', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
