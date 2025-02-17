/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// conditionals_test.dart
/// Unit tests for conditional calculations (e.g. always_comb, always_ff)
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

// TODO: ensure no multiple drivers on ff allowed (illegal in SV and makes no sense) [implemented, but add a test]

class LoopyCombModule extends Module {
  Logic get a => input('a');
  Logic get x => output('x');
  LoopyCombModule(Logic a) : super(name: 'loopycombmodule') {
    a = addInput('a', a);
    var x = addOutput('x');

    Combinational([
      x < a,
      x < ~x,
    ]);
  }
}

class CaseModule extends Module {
  CaseModule(Logic a, Logic b) : super(name: 'casemodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    var c = addOutput('c');
    var d = addOutput('d');
    var e = addOutput('e');

    Combinational([
      Case(swizzle([b,a]), [
          CaseItem(Const(LogicValues.fromString('01')), [
            c < 1,
            d < 0
          ]),
          CaseItem(Const(LogicValues.fromString('10')), [
            c < 1,
            d < 0,
          ]),
        ], defaultItem: [
          c < 0,
          d < 1,
        ],
        conditionalType: ConditionalType.unique
      ),
      CaseZ(swizzle([b,a]),[
          CaseItem(Const(LogicValues.fromString('z1')), [
            e < 1,
          ])
        ], defaultItem: [
          e < 0,
        ],
        conditionalType: ConditionalType.priority
      )
    ]);
  }
}

class IfBlockModule extends Module {
  IfBlockModule(Logic a, Logic b) : super(name: 'ifblockmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    var c = addOutput('c');
    var d = addOutput('d');

    Combinational([
      IfBlock([
        Iff(a & ~b, [
          c < 1,
          d < 0
        ]),
        ElseIf(b & ~a, [
          c < 1,
          d < 0
        ]),
        Else([
          c < 0,
          d < 1
        ])
      ])
    ]);
  }
}

class CombModule extends Module {

  CombModule(Logic a, Logic b, Logic d) : super(name: 'combmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    var y = addOutput('y');
    var z = addOutput('z');
    var x = addOutput('x');

    d = addInput('d', d, width:d.width);
    var q = addOutput('q', width:d.width);

    Combinational([
      If(a, then: [
          y < a,
          z < b,
          x < a & b,
          q < d,
      ], orElse: [ If(b, then: [
          y < b,
          z < a,
          q < 13,
      ], orElse: [
          y < 0,
          z < 1,
      ])])
    ]);
  }

}

class FFModule extends Module {

  FFModule(Logic a, Logic b, Logic d) : super(name: 'ffmodule') {
    a = addInput('a', a);
    b = addInput('b', b);
    var y = addOutput('y');
    var z = addOutput('z');
    var x = addOutput('x');

    d = addInput('d', d, width:d.width);
    var q = addOutput('q', width:d.width);

    FF(SimpleClockGenerator(10).clk, [
      If(a, then: [
          q < d,
          y < a,
          z < b,
          x < ~x,  // invert x when a
      ], orElse: [ 
        x < a,     // reset x to a when not a
        If(b, then: [
          y < b,
          z < a
        ], orElse: [
            y < 0,
            z < 1,
        ])]
      )
    ]);
  }
}

void main() {
  
  tearDown(() {
    Simulator.reset();
  });


  group('functional', () {
    test('conditional loopy comb', () async {
      var mod = LoopyCombModule(Logic());
      await mod.build();
      mod.a.put(1);
      expect(mod.x.valueInt, equals(0));
    });
  });

  group('simcompare', () {

    test('conditional comb', () async {
      var mod = CombModule(Logic(), Logic(), Logic(width: 10));
      await mod.build();
      var vectors = [
        Vector({'a': 0, 'b': 0, 'd':5}, {'y': 0, 'z': 1, 'x': LogicValue.x, 'q': LogicValue.x}),
        Vector({'a': 0, 'b': 1, 'd':6}, {'y': 1, 'z': 0, 'x': LogicValue.x, 'q': 13}),
        Vector({'a': 1, 'b': 0, 'd':7}, {'y': 1, 'z': 0, 'x': 0,            'q': 7}),
        Vector({'a': 1, 'b': 1, 'd':8}, {'y': 1, 'z': 1, 'x': 1,            'q': 8}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors,
        signalToWidthMap: {
          'd': 10,
          'q': 10
        }
      );
      expect(simResult, equals(true));
    });

    test('iffblock comb', () async {
      var mod = IfBlockModule(Logic(), Logic());
      await mod.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('case comb', () async {
      var mod = CaseModule(Logic(), Logic());
      await mod.build();
      var vectors = [
        Vector({'a': 0, 'b': 0}, {'c': 0, 'd': 1, 'e': 0}),
        Vector({'a': 0, 'b': 1}, {'c': 1, 'd': 0, 'e': 0}),
        Vector({'a': 1, 'b': 0}, {'c': 1, 'd': 0, 'e': 1}),
        Vector({'a': 1, 'b': 1}, {'c': 0, 'd': 1, 'e': 1}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors);
      expect(simResult, equals(true));
    });

    test('conditional ff', () async {
      var mod = FFModule(Logic(), Logic(), Logic(width:8));
      await mod.build();
      var vectors = [
        Vector({'a': 1,         'd': 1}, {}),
        Vector({'a': 0, 'b': 0, 'd': 2}, {                        'q': 1}),
        Vector({'a': 0, 'b': 1, 'd': 3}, {'y': 0, 'z': 1, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 0, 'd': 4}, {'y': 1, 'z': 0, 'x': 0, 'q': 1}),
        Vector({'a': 1, 'b': 1, 'd': 5}, {'y': 1, 'z': 0, 'x': 1, 'q': 4}),
        Vector({},                       {'y': 1, 'z': 1, 'x': 0, 'q': 5}),
      ];
      await SimCompare.checkFunctionalVector(mod, vectors);
      var simResult = SimCompare.iverilogVector(mod.generateSynth(), mod.runtimeType.toString(), vectors,
        signalToWidthMap: {'d':8, 'q':8}
      );
      expect(simResult, equals(true));
    });


  });
}