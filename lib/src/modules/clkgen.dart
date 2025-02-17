/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// clkgen.dart
/// A simple clock generator (non-synthesizable)
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';

/// A very simple, clock generator.  Generates a non-synthesizable SystemVerilog representation.
/// 
/// Set the frequency via [clockPeriod].
class SimpleClockGenerator extends Module with CustomSystemVerilog {
  final double clockPeriod;

  /// The generated clock.
  Logic get clk => output('clk');

  //TODO: consider making clock start at 1 instead of 0 (requires some tweaks to unit testing)
  
  SimpleClockGenerator(this.clockPeriod, {String name='clkgen'}) : super(name: name) {
    addOutput('clk');

    clk.glitch.listen((args) {
      Simulator.registerAction(Simulator.time + clockPeriod/2, () {
        clk.put(
          ~clk.value
        );
      });
    });
    clk.put(0);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName, Map<String,String> inputs, Map<String,String> outputs) {
    if(inputs.isNotEmpty || outputs.length != 1) {
      throw Exception('SimpleClockGenerator has exactly one output and no inputs.');
    }
    var clk = outputs['clk']!;
    return '''
// $instanceName
initial begin
  $clk = 0;
  forever begin
    #${clockPeriod~/2};
    $clk = ~$clk;
  end
end
''';
  }
}