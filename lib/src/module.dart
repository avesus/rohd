/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// module.dart
/// Definition for abstract module class
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'dart:async';
import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/uniquifier.dart';


//TODO: make a way to convert SV modules into ROHD
//  check out:  https://github.com/google/verible
//              https://github.com/alainmarcel/Surelog

/// Represents a synthesizable hardware entity with clearly defined interface boundaries.
/// 
/// Any hardware to be synthesized must be contained within a [Module].
/// This construct is similar to a SystemVerilog `module`.
abstract class Module {

  /// The name of this [Module].
  final String name;

  /// An internal list of sub-modules.
  final Set<Module> _modules = {};

  /// An internal list of internal-signals.
  /// 
  /// Used for waveform dump efficiency.
  final Set<Logic> _internalSignals = {};

  /// An internal list of inputs to this [Module].
  final Map<String, Logic> _inputs = {};
  /// An internal list of outputs to this [Module].
  final Map<String, Logic> _outputs = {};
  
  /// The parent [Module] of this [Module].
  /// 
  /// This only gets populated after its parent [Module], if it exists, has been built.
  Module? get parent => _parent;
  Module? _parent; // a cached copy of the parent, useful for debug and efficiency

  /// A map from input port names to this [Module] to corresponding [Logic] signals.
  Map<String, Logic> get inputs => UnmodifiableMapView<String,Logic>(_inputs);

  /// A map from output port names to this [Module] to corresponding [Logic] signals.
  Map<String, Logic> get outputs => UnmodifiableMapView<String,Logic>(_outputs);

  /// An [Iterable] of all [Module]s contained within this [Module].
  /// 
  /// This only gets populated after this [Module] has been built.
  Iterable<Module> get subModules => UnmodifiableListView<Module>(_modules);

  /// An [Iterable] of all [Logic]s contained within this [Module] which are *not* an input or output port of this [Module].
  /// 
  /// This does not contain any signals within submodules.
  Iterable<Logic> get internalSignals => UnmodifiableListView<Logic>(_internalSignals);

  /// An [Iterable] of all [Logic]s contained within this [Module], including inputs, outputs, and internal signals of this [Module].
  /// 
  /// This does not contain any signals within submodules.
  Iterable<Logic> get signals => CombinedListView([
    UnmodifiableListView(_inputs.values),
    UnmodifiableListView(_outputs.values),
    UnmodifiableListView(internalSignals),
  ]);

  /// Accesses the [Logic] associated with this [Module]s input port named [name].
  /// 
  /// Logic within this [Module] should consume this signal.
  Logic input(String name) => _inputs.containsKey(name) ? _inputs[name]! : throw Exception('Input name "$name" not found');

  /// Accesses the [Logic] associated with this [Module]s output port named [name].
  /// 
  /// Logic outside of this [Module] should consume this signal.  It is okay to consume this within this [Module] as well.
  Logic output(String name) => _outputs.containsKey(name) ? _outputs[name]! : throw Exception('Output name "$name" not found');

  /// Returns true iff [net] is the same [Logic] as the input port of this [Module] with the same name.
  bool isInput(Logic net) => _inputs[net.name] == net;

  /// Returns true iff [net] is the same [Logic] as the output port of this [Module] with the same name.
  bool isOutput(Logic net) => _outputs[net.name] == net;
  
  /// If this module has a [parent], after [build()] this will be a guaranteed unique name within its scope.
  String get uniqueInstanceName => 
    hasBuilt ? _uniqueInstanceName : throw Exception('Module must be built to access uniquified name.');
  String _uniqueInstanceName;

  Module({this.name = 'unnamed_module'}) :
    _uniqueInstanceName = name;

  /// Returns an [Iterable] of [Module]s representing the hierarchical path to this [Module].
  /// 
  /// The first element of the [Iterable] is the top-most hierarchy.
  /// The last element of the [Iterable] is this [Module].
  /// Only returns valid information after [build()].
  Iterable<Module> hierarchy() {
    if(!hasBuilt) throw Exception('Module must be built before accessing hierarchy.');
    Module? pModule = this;
    var hierarchyQueue = Queue<Module>(); 
    while(pModule != null) {
      hierarchyQueue.addFirst(pModule);
      pModule = pModule.parent;
    }
    return hierarchyQueue;
  }

  /// Indicates whether this [Module] has had the [build()] method called on it.
  bool get hasBuilt => _hasBuilt;
  bool _hasBuilt = false;
  
  /// Builds the [Module] and all [subModules] within it.
  /// 
  /// It is recommended not to override [build()] nor put logic in [build()] unless
  /// you have good reason to do so.  Aim to build up relevant logic in the constructor.
  /// 
  /// All logic within this [Module] *must* be defined *before* the call to
  /// `super.build()`.  When overriding this method, you should call `super.build()`
  /// as the last thing that you do, and you must always call it.
  /// 
  /// This method traverses connectivity inwards from this [Module]'s [inputs] and [outputs]
  /// to determine which [Module]s are contained within it.  During this process, it
  /// will set a variety of additional information within the hierarchy.
  /// 
  /// This function can be used to consume real wallclock time for things like
  /// starting up interactions with independent processes (e.g. cosimulation).
  /// 
  /// This function should only be called one time per [Module].
  @mustCallSuper
  Future<void> build() async {
    if(hasBuilt) throw Exception('Module already built.');

    // construct the list of modules within this module
    // 1) trace from outputs of this module back to inputs of this module
    for(var output in _outputs.values) {
      _traceOutputForModuleContents(output, dontAddSignal: true);
    }
    // 2) trace from inputs of all modules to inputs of this module
    for(var input in _inputs.values) {
      _traceInputForModuleContents(input, dontAddSignal: true);
    }

    for(var module in _modules) {
      await module.build();
    }

    // set unique module instance names for submodules
    var uniquifier = Uniquifier();
    for(var module in _modules) {
      module._uniqueInstanceName = uniquifier.getUniqueName(
        initialName: Sanitizer.sanitizeSV(module.name)
      );
    }

    _hasBuilt = true;
  }

  /// Adds a [Module] to this as a subModule.
  void _addModule(Module module) {
    if(module.parent != null) throw Exception('Module already has a parent');

    if(!_modules.contains(module)) {
      _modules.add(module);
    }
    module._parent = this;
  }

  /// A prefix to add to the beginning of any port name that is "unpreferred".
  static String get _unpreferredPrefix => '_';

  /// Makes a signal name "unpreferred" when considering between multiple possible signal names.
  /// 
  /// When logic is synthesized out (e.g. to SystemVerilog), there are cases where two
  /// signals might be logically equivalent (e.g. directly connected to each other).  In 
  /// those scenarios, one of the two signals is collapsed into the other.  If one of the two
  /// signals is "unpreferred", it will chose the other one for the final signal name.  Marking
  /// signals as "unpreferred" can have the effect of making generated output easier to read.
  @protected
  static String unpreferredName(String name) {
    //TODO: how to make sure there's no module name conflicts??
    return _unpreferredPrefix + name;
  }
  
  /// Returns true iff the signal name is "unpreferred".
  /// 
  /// See documentation for [unpreferredName] for more details.
  static bool isUnpreferred(String name) {
    return name.startsWith(_unpreferredPrefix);
  }

  /// Searches for [Logic]s and [Module]s within this [Module] from its inputs.
  void _traceInputForModuleContents(Logic signal, {bool dontAddSignal=false}) {
    if(isOutput(signal)) return;

    if(!signal.isInput && !signal.isOutput && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    var subModule = signal.isInput ? signal.parentModule : null;

    var subModuleParent = subModule?.parent;

    if(!dontAddSignal && signal.isOutput) {
      // somehow we have reached the output of a module which is not a submodule nor this module, bad!
      //TODO: add tests that this exception hits!
      throw Exception('Violation of input/output rules');
    }

    if(subModule != this && subModuleParent != null) {
      // we've already parsed down this path
      return;
    }

    if(subModule != null && subModule != this && (subModuleParent == null || subModuleParent == this) ) {
      // if the subModuleParent hasn't been set, or it is the current module, then trace it
      if(subModuleParent != this) {
        _addModule(subModule);
      }
      for (var subModuleOutput in subModule._outputs.values) {
        _traceInputForModuleContents(subModuleOutput, dontAddSignal: true);
      }
      for (var subModuleInput in subModule._inputs.values) {
        _traceOutputForModuleContents(subModuleInput, dontAddSignal: true);
      }
    } else {
      if(!dontAddSignal && !isInput(signal) && subModule == null) {
        _addInternalSignal(signal);
      }
      for (var dstConnection in signal.dstConnections) {
        _traceInputForModuleContents(dstConnection);
      }
    }
  }

  /// Searches for [Logic]s and [Module]s within this [Module] from its outputs.
  void _traceOutputForModuleContents(Logic signal, {bool dontAddSignal=false}) {
    if(isInput(signal)) return;

    if(!signal.isInput && !signal.isOutput && signal.parentModule != null) {
      // we've already parsed down this path
      return;
    }

    var subModule = signal.isOutput ? signal.parentModule : null;

    var subModuleParent = subModule?.parent;

    if(!dontAddSignal && signal.isInput) {
      // somehow we have reached the input of a module which is not a submodule nor this module, bad!
      throw Exception('Violation of input/output rules');
    }

    if(subModule != this && subModuleParent != null) {
      // we've already parsed down this path
      return;
    }

    if(subModule != null && subModule != this && (subModuleParent == null || subModuleParent == this) ) {
      // if the subModuleParent hasn't been set, or it is the current module, then trace it
      if(subModuleParent != this) {
        _addModule(subModule);
      }
      for (var subModuleInput in subModule._inputs.values) {
        _traceOutputForModuleContents(subModuleInput, dontAddSignal: true);
      }
      for (var subModuleOutput in subModule._outputs.values) {
        _traceInputForModuleContents(subModuleOutput, dontAddSignal: true);
      }
    } else {
      if(!dontAddSignal && !isOutput(signal) && subModule == null) {
        _addInternalSignal(signal);
      }
      if(signal.srcConnection != null) {
        _traceOutputForModuleContents(signal.srcConnection!);
      }
    }
  }

  /// Registers a signal as an internal signal.
  void _addInternalSignal(Logic signal) {
    _internalSignals.add(signal);
    
    // ignore: invalid_use_of_protected_member
    signal.setParentModule(this);
  }

  /// Checks whether a port name is safe to add (e.g. no duplicates).
  void _checkForSafePortName(String name) {
    if(!Sanitizer.isSanitary(name)) throw Exception('Invalid name:"$name", must be legal SystemVerilog');
    if(outputs.containsKey(name) || inputs.containsKey(name)) {
      throw Exception('Already defined a port with name $name');
    }
  }

  /// Registers a signal as an input to this [Module] and returns an input port that can be consumed.
  /// 
  /// The return value is the same as what is returned by [input()].
  @protected
  Logic addInput(String name, Logic x, {int width=1}) {
    _checkForSafePortName(name);
    if(x.width != width) throw Exception('Port width mismatch');
    _inputs[name] = Logic(name: name, width: width)..gets(x);
    
    // ignore: invalid_use_of_protected_member
    _inputs[name]!.setParentModule(this);
    
    return _inputs[name]!;
  }

  /// Registers an output to this [Module] and returns an output port that can be driven.
  /// 
  /// The return value is the same as what is returned by [output()].
  @protected
  Logic addOutput(String name, {int width=1}) {
    _checkForSafePortName(name);
    _outputs[name] = Logic(name: name, width: width);
    
    // ignore: invalid_use_of_protected_member
    _outputs[name]!.setParentModule(this);
    
    return _outputs[name]!;
  }

  @override
  String toString() {
    return '"$name" ($runtimeType)  :  ${_inputs.keys.toString()} => ${_outputs.keys.toString()}';
  }

  /// Returns a pretty-print [String] of the heirarchy of all [Module]s within this [Module].
  String hierarchyString([int indent=0]) {
    var padding = List.filled(indent, '  ').join();
    var hier = padding + '> ' + toString();
    for (var module in _modules) {
      hier += '\n' + module.hierarchyString(indent+1);
    }
    return hier;
  }
  
  /// Returns a synthesized version of this [Module].
  /// 
  /// Currently returns one long file in SystemVerilog, but in the future 
  /// may have other output formats, languages, files, etc.
  String generateSynth() {
    if(!_hasBuilt) {
      throw Exception('Module has not yet built!');
    }

    var synthHeader = '''
/**
 * Generated by ROHD - www.github.com/intel/rohd
 * Generation time: ${DateTime.now()}
 * ROHD author: Max Korbel <max.korbel@intel.com>
 */

''';
    return synthHeader + SynthBuilder(this, SystemVerilogSynthesizer()).getFileContents().join('\n\n////////////////////\n\n');
  }

}

//TODO: generate multiple SV files, one module per file
//TODO: add ability to add a header to generated files (e.g. copyright)

//TODO: warnings for unconnected ports?




