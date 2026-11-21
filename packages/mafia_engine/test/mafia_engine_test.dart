import 'package:contracts/contracts.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:test/test.dart';

void main() {
  test('MafiaEngine implements the GameEngine contract', () {
    const GameEngine engine = MafiaEngine();
    expect(engine, isA<GameEngine>());
  });
}
