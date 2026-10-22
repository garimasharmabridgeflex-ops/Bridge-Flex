class Branch {
  const Branch({
    required this.id,
    required this.nurseryId,
    required this.name,
    required this.address,
    required this.postcode,
    required this.city,
    this.phone = '',
    this.contactPerson = '',
    this.ofstedRegNumber = '',
    this.isPrimary = false,
  });

  final String id;
  final String nurseryId;
  final String name;
  final String address;
  final String postcode;
  final String city;
  final String phone;
  final String contactPerson;
  final String ofstedRegNumber;
  final bool isPrimary;

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
        id: json['id'] as String? ?? '',
        nurseryId: json['nurseryId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        postcode: json['postcode'] as String? ?? '',
        city: json['city'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        contactPerson: json['contactPerson'] as String? ?? '',
        ofstedRegNumber: json['ofstedRegNumber'] as String? ?? '',
        isPrimary: json['isPrimary'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'postcode': postcode,
        'city': city,
        'phone': phone,
        'contactPerson': contactPerson,
        'ofstedRegNumber': ofstedRegNumber,
        'isPrimary': isPrimary,
      };
}
