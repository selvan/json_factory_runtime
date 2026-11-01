import 'package:example/factories.dart';
import 'package:example/models/address.dart';
import 'package:example/models/event.dart';
import 'package:example/models/order.dart';
import 'package:example/models/user.dart';
import 'package:test/test.dart';

void main() {
  const models = ModelFactory();
  const api = ApiFactory();
  const keyField = '__type__';

  test('toJson writes the runtime key', () {
    expect(const User(id: '1', name: 'Ada').toJson(), {
      'id': '1',
      'name': 'Ada',
      keyField: 'user',
    });
    expect(JsonFactoryMixin.keyField, keyField);
    expect(JsonFactoryMapper.keyField, keyField);
  });

  test('fromKeyedJson rebuilds the right class from toJson output', () {
    final user = models.fromKeyedJsonAs<User>(
      const User(id: '1', name: 'Ada').toJson(),
    );
    expect(user.name, 'Ada');

    final address = models.fromKeyedJson(
      const Address(city: 'Chennai', zip: '600001').toJson(),
    );
    expect(address, isA<Address>());
    expect(models.mapperKeys, unorderedEquals(['user', 'address']));
  });

  test('nested objects carry their key too', () {
    final json = const Order(
      id: 'o1',
      total: 9.5,
      customer: User(id: '1', name: 'Ada'),
    ).toJson();
    expect(json[keyField], 'order');
    final customer = json['customer'] as Map<String, dynamic>;
    expect(customer[keyField], 'user');

    final order = api.fromKeyedJsonAs<Order>(json);
    expect(order.customer?.name, 'Ada');
    expect(models.fromKeyedJson(customer), isA<User>());
  });

  test('old keys still decode but are not listed', () {
    final address = models.fromKeyedJson({
      keyField: 'location',
      'city': 'Chennai',
      'zip': '600001',
    });
    expect(address, isA<Address>());
    expect(models.hasMapperKey('location'), isTrue);
    expect(models.mapperKeys, isNot(contains('location')));
    expect(
      (address as Address).toJson()[keyField],
      'address',
      reason: 'toJson writes the current key',
    );
  });

  test('named mixin has its own keys', () {
    expect(api.fromJsonByKey('user', {'login': 'ada'}), isA<ApiUser>());
    expect(api.hasMapperKey('address'), isFalse);
  });

  test('generated mapper classes work like the mixed-in classes', () {
    final json = const User(id: '1', name: 'Ada').toJson();
    expect(
      JsonFactoryMapper.fromKeyedJsonAs<User>(json).name,
      'Ada',
    );
    expect(
      ApiMapper.fromJsonByKey('user', {'login': 'ada'}),
      isA<ApiUser>(),
    );
  });

  test('a final field key is written and decodes', () {
    final json = const ApiUser(login: 'ada').toJson();
    expect(json, {'login': 'ada', keyField: 'user'});
    expect(ApiMapper.fromKeyedJson(json), isA<ApiUser>());
  });

  test('an enum @JsonValue key is written and decodes', () {
    final json = const ApiEvent(name: 'launch').toJson();
    expect(json, {'name': 'launch', keyField: 'api_event'});
    expect(ApiMapper.fromKeyedJsonAs<ApiEvent>(json).name, 'launch');
    expect(ApiMapper.hasMapperKey('api_event'), isTrue);
  });

  test('missing or unknown key throws', () {
    expect(() => models.fromKeyedJson({'id': '1'}), throwsArgumentError);
    expect(() => models.fromJsonByKey('nope', {}), throwsArgumentError);
  });
}
