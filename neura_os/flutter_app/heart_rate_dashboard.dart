import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class HeartRateDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Heart Rate Dashboard')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('health_data')
            .orderBy('timestamp', descending: true)
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return CircularProgressIndicator();
          final docs = snapshot.data!.docs;
          final points = docs.map((doc) {
            final bpm = doc['heartRate'];
            final index = docs.indexOf(doc);
            return FlSpot(index.toDouble(), bpm.toDouble());
          }).toList();
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(spots: points, isCurved: true),
              ],
            )),
          );
        },
      ),
    );
  }
}