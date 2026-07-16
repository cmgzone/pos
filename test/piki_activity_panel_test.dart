import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/piki_ai_job_service.dart';
import 'package:pos_app/widgets/piki_activity_panel.dart';

void main() {
  testWidgets('Piki panel shows only the actual current backend stage', (
    tester,
  ) async {
    const job = PikiAiJob(
      id: 'job-1',
      jobType: 'storefront_theme',
      status: 'running',
      progress: 52,
      totalSteps: 5,
      completedSteps: 2,
      currentStep: 'Designing the storefront',
    );
    const events = [
      PikiAiJobEvent(
        id: 'event-1',
        eventType: 'storefront_brief',
        level: 'info',
        title: 'Reading your storefront brief',
        message: 'Reading the saved request.',
      ),
      PikiAiJobEvent(
        id: 'event-2',
        eventType: 'storefront_designing',
        level: 'info',
        title: 'Designing the storefront',
        message: 'Creating the visual direction and section order.',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PikiActivityPanel(job: job, events: events),
        ),
      ),
    );

    expect(find.text('Designing the storefront'), findsOneWidget);
    expect(
      find.text('Creating the visual direction and section order.'),
      findsOneWidget,
    );
    expect(find.text('Reading your storefront brief'), findsNothing);
    expect(find.text('Stage 3 of 5'), findsOneWidget);
  });

  testWidgets('Piki panel fades to the saved completion event', (tester) async {
    const runningJob = PikiAiJob(
      id: 'job-1',
      jobType: 'storefront_theme',
      status: 'running',
      progress: 78,
      totalSteps: 5,
      completedSteps: 3,
      currentStep: 'Checking the storefront',
    );
    const completedJob = PikiAiJob(
      id: 'job-1',
      jobType: 'storefront_theme',
      status: 'completed',
      progress: 100,
      totalSteps: 5,
      completedSteps: 5,
      currentStep: 'Storefront draft ready',
    );
    const checking = PikiAiJobEvent(
      id: 'event-1',
      eventType: 'storefront_validating',
      level: 'info',
      title: 'Checking the storefront',
      message: 'Validating the customer experience.',
    );
    const ready = PikiAiJobEvent(
      id: 'event-2',
      eventType: 'storefront_ready',
      level: 'info',
      title: 'Storefront draft ready',
      message: 'Open the exact website preview.',
    );

    Widget build(PikiAiJob job, List<PikiAiJobEvent> events) => MaterialApp(
      home: Scaffold(
        body: PikiActivityPanel(job: job, events: events),
      ),
    );

    await tester.pumpWidget(build(runningJob, const [checking]));
    await tester.pumpWidget(build(completedJob, const [checking, ready]));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Storefront draft ready'), findsOneWidget);
    expect(find.text('Open the exact website preview.'), findsOneWidget);
    expect(find.text('Checking the storefront'), findsNothing);
    expect(find.text('Complete'), findsOneWidget);
  });
}
