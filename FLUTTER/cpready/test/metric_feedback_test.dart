/// Grading rules for the live and summary capsules.

import 'package:flutter_test/flutter_test.dart';

import 'package:cpready/src/core/feedback/metric_feedback.dart';

void main() {
  test('a live stroke without full recoil grades poor, not neutral', () {
    expect(recoilRating(0), MetricRating.poor);
    expect(recoilRating(100), MetricRating.good);
    expect(recoilRating(null), isNull);
  });

  test('session recoil compliance is graded against 90 %', () {
    expect(recoilRating(89), MetricRating.poor);
    expect(recoilRating(90), MetricRating.good);
    expect(recoilRating(98), MetricRating.good);
  });

  test('estimated recoil is shown but not graded', () {
    expect(recoilRating(0, estimated: true), isNull);
    expect(recoilRating(100, estimated: true), isNull);
  });

  test('CCF is graded against the AHA minimum of 60 %', () {
    expect(ccfRating(59), MetricRating.poor);
    expect(ccfRating(60), MetricRating.good);
    expect(ccfRating(null), isNull);
  });
}
