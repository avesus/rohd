/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// counter_wintf_test.dart
/// Unit tests for a basic counter with an interface
/// 
/// 2021 May 25
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

enum CounterDirection {inward, outward}
class CounterInterface extends Interface<CounterDirection> {

  // TODO: interfaces within interfaces
  
  Logic get en => port('en');
  Logic get reset => port('reset');
  Logic get val => port('val');

  final int width;
  CounterInterface(this.width) {
    setPorts([
      Port('en'),
      Port('reset')
    ], [CounterDirection.inward]);

    setPorts([
      Port('val', width),
    ], [CounterDirection.outward]);
  }

}

class Counter extends Module {
  
  late final CounterInterface intf;
  Counter(CounterInterface intf) {
    this.intf = CounterInterface(intf.width)
      ..connectIO(this, intf, 
        inputTags: {CounterDirection.inward}, 
        outputTags: {CounterDirection.outward}
      );
    
    _buildLogic();
  }

  void _buildLogic() {
    var nextVal = Logic(name: 'nextVal', width: intf.width);
    
    nextVal <= intf.val + 1;

    FF( (SimpleClockGenerator(10).clk), [
      If(intf.reset, then:[
        intf.val < 0
      ], orElse: [If(intf.en, then: [
        intf.val < nextVal
      ])])
    ]);
  }
}


void main() {
  
  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {

    test('counter', () async {
      var mod = Counter(CounterInterface(8));
      await mod.build();
      var vectors = [
        Vector({'en': 0, 'reset': 1}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors,
        signalToWidthMap: {'val':8}
      );
      expect(simResult, equals(true));
    });


  });
}

