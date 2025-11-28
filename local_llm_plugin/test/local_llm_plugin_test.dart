import 'package:flutter_test/flutter_test.dart';
import 'package:local_llm_plugin/local_llm_plugin.dart';
import 'package:local_llm_plugin/local_llm_plugin_platform_interface.dart';
import 'package:local_llm_plugin/local_llm_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockLocalLlmPluginPlatform
    with MockPlatformInterfaceMixin
    implements LocalLlmPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String> loadModel(String modelPath) => Future.value('Mock model loaded');

  @override
  Future<String> generateResponse(String prompt) => Future.value('Mock response');

  @override
  Future<String> freeModel() => Future.value('Mock model freed');

  @override
  Future<void> generateResponseStreaming(
    String prompt,
    void Function(String) onToken,
    void Function(String) onComplete, {
    int maxTokens = 200,
  }) async {
    // Mock streaming implementation
    onToken('Mock token');
    onComplete('Mock complete response');
  }
}

void main() {
  final LocalLlmPluginPlatform initialPlatform = LocalLlmPluginPlatform.instance;

  test('$MethodChannelLocalLlmPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelLocalLlmPlugin>());
  });

  test('getPlatformVersion', () async {
    LocalLlmPlugin localLlmPlugin = LocalLlmPlugin();
    MockLocalLlmPluginPlatform fakePlatform = MockLocalLlmPluginPlatform();
    LocalLlmPluginPlatform.instance = fakePlatform;

    expect(await localLlmPlugin.getPlatformVersion(), '42');
  });
}
