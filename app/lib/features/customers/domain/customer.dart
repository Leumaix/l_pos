/// A customer account with a running credit balance. This is a minimal
/// slice of the eventual Customers feature — just enough for Payment's
/// "customer account" method to attach a credit sale to someone. The
/// dedicated Customers/Customer-detail screens (search, filters, full
/// transaction history) build on top of this same model, they don't
/// replace it.
class Customer {
  final String id;
  final String name;
  final String phone;
  final int balance; // whole naira owed to the business

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
  });

  Customer copyWith({int? balance}) =>
      Customer(id: id, name: name, phone: phone, balance: balance ?? this.balance);
}
