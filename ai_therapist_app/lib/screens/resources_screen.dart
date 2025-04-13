// lib/screens/resources_screen.dart
import 'package:flutter/material.dart';

class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mental Health Resources'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ResourceCategory(
            title: 'Crisis Support',
            resources: [
              Resource(
                title: 'National Suicide Prevention Lifeline',
                description: 'Call or text 988 (US)',
                type: ResourceType.hotline,
              ),
              Resource(
                title: 'Crisis Text Line',
                description: 'Text HOME to 741741 (US)',
                type: ResourceType.hotline,
              ),
            ],
          ),
          SizedBox(height: 16),
          ResourceCategory(
            title: 'Educational Articles',
            resources: [
              Resource(
                title: 'Understanding Anxiety',
                description: 'Learn about anxiety symptoms and coping strategies',
                type: ResourceType.article,
              ),
              Resource(
                title: 'Dealing with Depression',
                description: 'Signs, symptoms, and treatment options',
                type: ResourceType.article,
              ),
              Resource(
                title: 'Stress Management Techniques',
                description: 'Practical ways to reduce stress in daily life',
                type: ResourceType.article,
              ),
            ],
          ),
          SizedBox(height: 16),
          ResourceCategory(
            title: 'Guided Exercises',
            resources: [
              Resource(
                title: 'Deep Breathing',
                description: '5-minute guided breathing exercise',
                type: ResourceType.exercise,
              ),
              Resource(
                title: 'Progressive Muscle Relaxation',
                description: '10-minute relaxation technique',
                type: ResourceType.exercise,
              ),
              Resource(
                title: 'Mindfulness Meditation',
                description: '15-minute guided meditation',
                type: ResourceType.exercise,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum ResourceType {
  article,
  video,
  exercise,
  hotline,
}

class Resource {
  final String title;
  final String description;
  final ResourceType type;

  const Resource({
    required this.title,
    required this.description,
    required this.type,
  });
}

class ResourceCategory extends StatelessWidget {
  final String title;
  final List<Resource> resources;

  const ResourceCategory({
    Key? key,
    required this.title,
    required this.resources,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...resources.map((resource) => ResourceTile(resource: resource)),
      ],
    );
  }
}

class ResourceTile extends StatelessWidget {
  final Resource resource;

  const ResourceTile({
    Key? key,
    required this.resource,
  }) : super(key: key);

  IconData _getIcon() {
    switch (resource.type) {
      case ResourceType.article:
        return Icons.article_outlined;
      case ResourceType.video:
        return Icons.video_library_outlined;
      case ResourceType.exercise:
        return Icons.self_improvement_outlined;
      case ResourceType.hotline:
        return Icons.phone_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(_getIcon(), size: 32),
        title: Text(resource.title),
        subtitle: Text(resource.description),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          // Open resource
        },
      ),
    );
  }
}