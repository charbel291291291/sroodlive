import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Country data
// ─────────────────────────────────────────────────────────────────────────────

class Country {
  const Country({
    required this.name,
    required this.code,
    required this.flag,
  });

  final String name;
  final String code; // ISO 3166-1 alpha-2
  final String flag; // emoji

  String get display => '$flag $name';
}

// Full world country list — name, ISO code, flag emoji.
// Flag emoji is derived from the ISO code: each letter maps to a regional
// indicator symbol (U+1F1E6–U+1F1FF). Stored literally here for simplicity.
const List<Country> kAllCountries = [
  Country(name: 'Afghanistan', code: 'AF', flag: '🇦🇫'),
  Country(name: 'Albania', code: 'AL', flag: '🇦🇱'),
  Country(name: 'Algeria', code: 'DZ', flag: '🇩🇿'),
  Country(name: 'Andorra', code: 'AD', flag: '🇦🇩'),
  Country(name: 'Angola', code: 'AO', flag: '🇦🇴'),
  Country(name: 'Antigua & Barbuda', code: 'AG', flag: '🇦🇬'),
  Country(name: 'Argentina', code: 'AR', flag: '🇦🇷'),
  Country(name: 'Armenia', code: 'AM', flag: '🇦🇲'),
  Country(name: 'Australia', code: 'AU', flag: '🇦🇺'),
  Country(name: 'Austria', code: 'AT', flag: '🇦🇹'),
  Country(name: 'Azerbaijan', code: 'AZ', flag: '🇦🇿'),
  Country(name: 'Bahamas', code: 'BS', flag: '🇧🇸'),
  Country(name: 'Bahrain', code: 'BH', flag: '🇧🇭'),
  Country(name: 'Bangladesh', code: 'BD', flag: '🇧🇩'),
  Country(name: 'Barbados', code: 'BB', flag: '🇧🇧'),
  Country(name: 'Belarus', code: 'BY', flag: '🇧🇾'),
  Country(name: 'Belgium', code: 'BE', flag: '🇧🇪'),
  Country(name: 'Belize', code: 'BZ', flag: '🇧🇿'),
  Country(name: 'Benin', code: 'BJ', flag: '🇧🇯'),
  Country(name: 'Bhutan', code: 'BT', flag: '🇧🇹'),
  Country(name: 'Bolivia', code: 'BO', flag: '🇧🇴'),
  Country(name: 'Bosnia & Herzegovina', code: 'BA', flag: '🇧🇦'),
  Country(name: 'Botswana', code: 'BW', flag: '🇧🇼'),
  Country(name: 'Brazil', code: 'BR', flag: '🇧🇷'),
  Country(name: 'Brunei', code: 'BN', flag: '🇧🇳'),
  Country(name: 'Bulgaria', code: 'BG', flag: '🇧🇬'),
  Country(name: 'Burkina Faso', code: 'BF', flag: '🇧🇫'),
  Country(name: 'Burundi', code: 'BI', flag: '🇧🇮'),
  Country(name: 'Cambodia', code: 'KH', flag: '🇰🇭'),
  Country(name: 'Cameroon', code: 'CM', flag: '🇨🇲'),
  Country(name: 'Canada', code: 'CA', flag: '🇨🇦'),
  Country(name: 'Cape Verde', code: 'CV', flag: '🇨🇻'),
  Country(name: 'Central African Republic', code: 'CF', flag: '🇨🇫'),
  Country(name: 'Chad', code: 'TD', flag: '🇹🇩'),
  Country(name: 'Chile', code: 'CL', flag: '🇨🇱'),
  Country(name: 'China', code: 'CN', flag: '🇨🇳'),
  Country(name: 'Colombia', code: 'CO', flag: '🇨🇴'),
  Country(name: 'Comoros', code: 'KM', flag: '🇰🇲'),
  Country(name: 'Congo', code: 'CG', flag: '🇨🇬'),
  Country(name: 'Costa Rica', code: 'CR', flag: '🇨🇷'),
  Country(name: 'Croatia', code: 'HR', flag: '🇭🇷'),
  Country(name: 'Cuba', code: 'CU', flag: '🇨🇺'),
  Country(name: 'Cyprus', code: 'CY', flag: '🇨🇾'),
  Country(name: 'Czech Republic', code: 'CZ', flag: '🇨🇿'),
  Country(name: 'Denmark', code: 'DK', flag: '🇩🇰'),
  Country(name: 'Djibouti', code: 'DJ', flag: '🇩🇯'),
  Country(name: 'Dominican Republic', code: 'DO', flag: '🇩🇴'),
  Country(name: 'DR Congo', code: 'CD', flag: '🇨🇩'),
  Country(name: 'Ecuador', code: 'EC', flag: '🇪🇨'),
  Country(name: 'Egypt', code: 'EG', flag: '🇪🇬'),
  Country(name: 'El Salvador', code: 'SV', flag: '🇸🇻'),
  Country(name: 'Equatorial Guinea', code: 'GQ', flag: '🇬🇶'),
  Country(name: 'Eritrea', code: 'ER', flag: '🇪🇷'),
  Country(name: 'Estonia', code: 'EE', flag: '🇪🇪'),
  Country(name: 'Eswatini', code: 'SZ', flag: '🇸🇿'),
  Country(name: 'Ethiopia', code: 'ET', flag: '🇪🇹'),
  Country(name: 'Fiji', code: 'FJ', flag: '🇫🇯'),
  Country(name: 'Finland', code: 'FI', flag: '🇫🇮'),
  Country(name: 'France', code: 'FR', flag: '🇫🇷'),
  Country(name: 'Gabon', code: 'GA', flag: '🇬🇦'),
  Country(name: 'Gambia', code: 'GM', flag: '🇬🇲'),
  Country(name: 'Georgia', code: 'GE', flag: '🇬🇪'),
  Country(name: 'Germany', code: 'DE', flag: '🇩🇪'),
  Country(name: 'Ghana', code: 'GH', flag: '🇬🇭'),
  Country(name: 'Greece', code: 'GR', flag: '🇬🇷'),
  Country(name: 'Grenada', code: 'GD', flag: '🇬🇩'),
  Country(name: 'Guatemala', code: 'GT', flag: '🇬🇹'),
  Country(name: 'Guinea', code: 'GN', flag: '🇬🇳'),
  Country(name: 'Guinea-Bissau', code: 'GW', flag: '🇬🇼'),
  Country(name: 'Guyana', code: 'GY', flag: '🇬🇾'),
  Country(name: 'Haiti', code: 'HT', flag: '🇭🇹'),
  Country(name: 'Honduras', code: 'HN', flag: '🇭🇳'),
  Country(name: 'Hungary', code: 'HU', flag: '🇭🇺'),
  Country(name: 'Iceland', code: 'IS', flag: '🇮🇸'),
  Country(name: 'India', code: 'IN', flag: '🇮🇳'),
  Country(name: 'Indonesia', code: 'ID', flag: '🇮🇩'),
  Country(name: 'Iran', code: 'IR', flag: '🇮🇷'),
  Country(name: 'Iraq', code: 'IQ', flag: '🇮🇶'),
  Country(name: 'Ireland', code: 'IE', flag: '🇮🇪'),
  Country(name: 'Italy', code: 'IT', flag: '🇮🇹'),
  Country(name: 'Ivory Coast', code: 'CI', flag: '🇨🇮'),
  Country(name: 'Jamaica', code: 'JM', flag: '🇯🇲'),
  Country(name: 'Japan', code: 'JP', flag: '🇯🇵'),
  Country(name: 'Jordan', code: 'JO', flag: '🇯🇴'),
  Country(name: 'Kazakhstan', code: 'KZ', flag: '🇰🇿'),
  Country(name: 'Kenya', code: 'KE', flag: '🇰🇪'),
  Country(name: 'Kiribati', code: 'KI', flag: '🇰🇮'),
  Country(name: 'Kosovo', code: 'XK', flag: '🇽🇰'),
  Country(name: 'Kuwait', code: 'KW', flag: '🇰🇼'),
  Country(name: 'Kyrgyzstan', code: 'KG', flag: '🇰🇬'),
  Country(name: 'Laos', code: 'LA', flag: '🇱🇦'),
  Country(name: 'Latvia', code: 'LV', flag: '🇱🇻'),
  Country(name: 'Lebanon', code: 'LB', flag: '🇱🇧'),
  Country(name: 'Lesotho', code: 'LS', flag: '🇱🇸'),
  Country(name: 'Liberia', code: 'LR', flag: '🇱🇷'),
  Country(name: 'Libya', code: 'LY', flag: '🇱🇾'),
  Country(name: 'Liechtenstein', code: 'LI', flag: '🇱🇮'),
  Country(name: 'Lithuania', code: 'LT', flag: '🇱🇹'),
  Country(name: 'Luxembourg', code: 'LU', flag: '🇱🇺'),
  Country(name: 'Madagascar', code: 'MG', flag: '🇲🇬'),
  Country(name: 'Malawi', code: 'MW', flag: '🇲🇼'),
  Country(name: 'Malaysia', code: 'MY', flag: '🇲🇾'),
  Country(name: 'Maldives', code: 'MV', flag: '🇲🇻'),
  Country(name: 'Mali', code: 'ML', flag: '🇲🇱'),
  Country(name: 'Malta', code: 'MT', flag: '🇲🇹'),
  Country(name: 'Marshall Islands', code: 'MH', flag: '🇲🇭'),
  Country(name: 'Mauritania', code: 'MR', flag: '🇲🇷'),
  Country(name: 'Mauritius', code: 'MU', flag: '🇲🇺'),
  Country(name: 'Mexico', code: 'MX', flag: '🇲🇽'),
  Country(name: 'Micronesia', code: 'FM', flag: '🇫🇲'),
  Country(name: 'Moldova', code: 'MD', flag: '🇲🇩'),
  Country(name: 'Monaco', code: 'MC', flag: '🇲🇨'),
  Country(name: 'Mongolia', code: 'MN', flag: '🇲🇳'),
  Country(name: 'Montenegro', code: 'ME', flag: '🇲🇪'),
  Country(name: 'Morocco', code: 'MA', flag: '🇲🇦'),
  Country(name: 'Mozambique', code: 'MZ', flag: '🇲🇿'),
  Country(name: 'Myanmar', code: 'MM', flag: '🇲🇲'),
  Country(name: 'Namibia', code: 'NA', flag: '🇳🇦'),
  Country(name: 'Nauru', code: 'NR', flag: '🇳🇷'),
  Country(name: 'Nepal', code: 'NP', flag: '🇳🇵'),
  Country(name: 'Netherlands', code: 'NL', flag: '🇳🇱'),
  Country(name: 'New Zealand', code: 'NZ', flag: '🇳🇿'),
  Country(name: 'Nicaragua', code: 'NI', flag: '🇳🇮'),
  Country(name: 'Niger', code: 'NE', flag: '🇳🇪'),
  Country(name: 'Nigeria', code: 'NG', flag: '🇳🇬'),
  Country(name: 'North Korea', code: 'KP', flag: '🇰🇵'),
  Country(name: 'North Macedonia', code: 'MK', flag: '🇲🇰'),
  Country(name: 'Norway', code: 'NO', flag: '🇳🇴'),
  Country(name: 'Oman', code: 'OM', flag: '🇴🇲'),
  Country(name: 'Pakistan', code: 'PK', flag: '🇵🇰'),
  Country(name: 'Palau', code: 'PW', flag: '🇵🇼'),
  Country(name: 'Palestine', code: 'PS', flag: '🇵🇸'),
  Country(name: 'Panama', code: 'PA', flag: '🇵🇦'),
  Country(name: 'Papua New Guinea', code: 'PG', flag: '🇵🇬'),
  Country(name: 'Paraguay', code: 'PY', flag: '🇵🇾'),
  Country(name: 'Peru', code: 'PE', flag: '🇵🇪'),
  Country(name: 'Philippines', code: 'PH', flag: '🇵🇭'),
  Country(name: 'Poland', code: 'PL', flag: '🇵🇱'),
  Country(name: 'Portugal', code: 'PT', flag: '🇵🇹'),
  Country(name: 'Qatar', code: 'QA', flag: '🇶🇦'),
  Country(name: 'Romania', code: 'RO', flag: '🇷🇴'),
  Country(name: 'Russia', code: 'RU', flag: '🇷🇺'),
  Country(name: 'Rwanda', code: 'RW', flag: '🇷🇼'),
  Country(name: 'Saint Kitts & Nevis', code: 'KN', flag: '🇰🇳'),
  Country(name: 'Saint Lucia', code: 'LC', flag: '🇱🇨'),
  Country(name: 'Saint Vincent', code: 'VC', flag: '🇻🇨'),
  Country(name: 'Samoa', code: 'WS', flag: '🇼🇸'),
  Country(name: 'San Marino', code: 'SM', flag: '🇸🇲'),
  Country(name: 'São Tomé & Príncipe', code: 'ST', flag: '🇸🇹'),
  Country(name: 'Saudi Arabia', code: 'SA', flag: '🇸🇦'),
  Country(name: 'Senegal', code: 'SN', flag: '🇸🇳'),
  Country(name: 'Serbia', code: 'RS', flag: '🇷🇸'),
  Country(name: 'Seychelles', code: 'SC', flag: '🇸🇨'),
  Country(name: 'Sierra Leone', code: 'SL', flag: '🇸🇱'),
  Country(name: 'Singapore', code: 'SG', flag: '🇸🇬'),
  Country(name: 'Slovakia', code: 'SK', flag: '🇸🇰'),
  Country(name: 'Slovenia', code: 'SI', flag: '🇸🇮'),
  Country(name: 'Solomon Islands', code: 'SB', flag: '🇸🇧'),
  Country(name: 'Somalia', code: 'SO', flag: '🇸🇴'),
  Country(name: 'South Africa', code: 'ZA', flag: '🇿🇦'),
  Country(name: 'South Korea', code: 'KR', flag: '🇰🇷'),
  Country(name: 'South Sudan', code: 'SS', flag: '🇸🇸'),
  Country(name: 'Spain', code: 'ES', flag: '🇪🇸'),
  Country(name: 'Sri Lanka', code: 'LK', flag: '🇱🇰'),
  Country(name: 'Sudan', code: 'SD', flag: '🇸🇩'),
  Country(name: 'Suriname', code: 'SR', flag: '🇸🇷'),
  Country(name: 'Sweden', code: 'SE', flag: '🇸🇪'),
  Country(name: 'Switzerland', code: 'CH', flag: '🇨🇭'),
  Country(name: 'Syria', code: 'SY', flag: '🇸🇾'),
  Country(name: 'Taiwan', code: 'TW', flag: '🇹🇼'),
  Country(name: 'Tajikistan', code: 'TJ', flag: '🇹🇯'),
  Country(name: 'Tanzania', code: 'TZ', flag: '🇹🇿'),
  Country(name: 'Thailand', code: 'TH', flag: '🇹🇭'),
  Country(name: 'Timor-Leste', code: 'TL', flag: '🇹🇱'),
  Country(name: 'Togo', code: 'TG', flag: '🇹🇬'),
  Country(name: 'Tonga', code: 'TO', flag: '🇹🇴'),
  Country(name: 'Trinidad & Tobago', code: 'TT', flag: '🇹🇹'),
  Country(name: 'Tunisia', code: 'TN', flag: '🇹🇳'),
  Country(name: 'Turkey', code: 'TR', flag: '🇹🇷'),
  Country(name: 'Turkmenistan', code: 'TM', flag: '🇹🇲'),
  Country(name: 'Tuvalu', code: 'TV', flag: '🇹🇻'),
  Country(name: 'Uganda', code: 'UG', flag: '🇺🇬'),
  Country(name: 'Ukraine', code: 'UA', flag: '🇺🇦'),
  Country(name: 'UAE', code: 'AE', flag: '🇦🇪'),
  Country(name: 'United Kingdom', code: 'GB', flag: '🇬🇧'),
  Country(name: 'United States', code: 'US', flag: '🇺🇸'),
  Country(name: 'Uruguay', code: 'UY', flag: '🇺🇾'),
  Country(name: 'Uzbekistan', code: 'UZ', flag: '🇺🇿'),
  Country(name: 'Vanuatu', code: 'VU', flag: '🇻🇺'),
  Country(name: 'Vatican City', code: 'VA', flag: '🇻🇦'),
  Country(name: 'Venezuela', code: 'VE', flag: '🇻🇪'),
  Country(name: 'Vietnam', code: 'VN', flag: '🇻🇳'),
  Country(name: 'Yemen', code: 'YE', flag: '🇾🇪'),
  Country(name: 'Zambia', code: 'ZM', flag: '🇿🇲'),
  Country(name: 'Zimbabwe', code: 'ZW', flag: '🇿🇼'),
];

/// Find a [Country] by stored name, code, or partial match (for legacy values).
Country? countryFromStored(String? stored) {
  if (stored == null || stored.isEmpty) return null;
  final s = stored.trim().toLowerCase();
  // Exact name or code match first.
  for (final c in kAllCountries) {
    if (c.name.toLowerCase() == s || c.code.toLowerCase() == s) return c;
  }
  // Partial name match (handles legacy free-text like "Saudi Arabia", "KSA").
  for (final c in kAllCountries) {
    if (c.name.toLowerCase().contains(s) || s.contains(c.name.toLowerCase())) {
      return c;
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// CountryPickerSheet
// ─────────────────────────────────────────────────────────────────────────────

/// Opens a premium dark-purple bottom sheet listing all world countries with
/// flag emojis.  Returns the selected [Country], or null if dismissed.
Future<Country?> showCountryPicker(
  BuildContext context, {
  Country? selected,
  bool isArabic = false,
}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CountryPickerSheet(
      selected: selected,
      isArabic: isArabic,
    ),
  );
}

class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({
    super.key,
    this.selected,
    this.isArabic = false,
  });

  final Country? selected;
  final bool isArabic;

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  final _search = TextEditingController();
  List<Country> _filtered = kAllCountries;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? kAllCountries
          : kAllCountries
              .where((c) =>
                  c.name.toLowerCase().contains(q) ||
                  c.code.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF120430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              textDirection:
                  widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
              children: [
                const Icon(
                  Icons.public_rounded,
                  color: Color(0xFFF0C15A),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.isArabic ? 'اختر الدولة' : 'Select Country',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.30),
                ),
              ),
              child: TextField(
                controller: _search,
                autofocus: false,
                textDirection:
                    widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.isArabic ? 'بحث عن دولة' : 'Search country',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.40),
                    size: 20,
                  ),
                  suffixIcon: _search.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: Colors.white.withValues(alpha: 0.40),
                            size: 18,
                          ),
                          onPressed: () {
                            _search.clear();
                            HapticFeedback.selectionClick();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Divider
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
          ),

          // Country list
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      widget.isArabic ? 'لا توجد نتائج' : 'No results found',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final country = _filtered[i];
                      final isSelected =
                          widget.selected?.code == country.code;
                      return _CountryRow(
                        country: country,
                        isSelected: isSelected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop(country);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.isSelected,
    required this.onTap,
  });

  final Country country;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFF8B26D9).withValues(alpha: 0.12),
        highlightColor: const Color(0xFF8B26D9).withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: isSelected
              ? BoxDecoration(
                  color: const Color(0xFF8B26D9).withValues(alpha: 0.12),
                  border: Border(
                    left: BorderSide(
                      color: const Color(0xFFF0C15A).withValues(alpha: 0.70),
                      width: 2,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              // Flag emoji
              Text(
                country.flag,
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 14),

              // Country name
              Expanded(
                child: Text(
                  country.name,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),

              // ISO code
              Text(
                country.code,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 10),

              // Gold checkmark for selected
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFFF0C15A),
                  size: 18,
                )
              else
                const SizedBox(width: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CountrySelector  (tappable field for use inside edit-profile forms)
// ─────────────────────────────────────────────────────────────────────────────

/// A tappable form-field look-alike that opens [CountryPickerSheet] on tap.
/// Style matches the premium purple/gold profile form.
class CountrySelector extends StatelessWidget {
  const CountrySelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.isArabic,
  });

  final Country? selected;
  final ValueChanged<Country> onSelected;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final hasValue = selected != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () async {
          HapticFeedback.selectionClick();
          final picked = await showCountryPicker(
            context,
            selected: selected,
            isArabic: isArabic,
          );
          if (picked != null) onSelected(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasValue
                  ? const Color(0xFFF0C15A).withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.18),
              width: 1.2,
            ),
          ),
          child: Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              // Flag + name OR placeholder
              Expanded(
                child: hasValue
                    ? Row(
                        textDirection:
                            isArabic ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          Text(
                            selected!.flag,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              selected!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        isArabic ? 'اختر دولتك' : 'Select your country',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 14,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.45),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
