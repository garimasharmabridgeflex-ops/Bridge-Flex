package function

import "testing"

func TestCompanyAdminSettingsIncludesUnpublishedValues(t *testing.T) {
	conf := CompanyConfig{
		CompanyName:   CompanyField{Value: "K Flex Ltd", Published: false},
		CompanyNumber: CompanyField{Value: "01234567", Published: false},
		VATNumber:     CompanyField{Value: "GB123456789", Published: true},
	}
	company := adminCompanySettings(conf)
	if company["companyName"].Value != "K Flex Ltd" || company["companyName"].Published {
		t.Fatal("admin settings must retain unpublished company values and their publication state")
	}
	if company["vatNumber"].Value != "GB123456789" || !company["vatNumber"].Published {
		t.Fatal("admin settings must retain published values and their publication state")
	}
}
