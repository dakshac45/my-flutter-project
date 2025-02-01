import 'package:flutter/material.dart';
import 'ui_components.dart';
import 'api_service.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  _CalculatorScreenState createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  // Controllers for input fields
  final TextEditingController revenueController = TextEditingController();
  final TextEditingController loanController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController amountController = TextEditingController();

  // Variables to store configuration and user inputs
  String dropdownValue = "";
  String repaymentFrequency = "";
  String repaymentDelay = "";

  // Variables to store calculated results
  double revenueSharePercentage = 0.0;
  double totalRevenueShare = 0.0;
  double feePercentage = 0.0;
  double feeAmount = 0.0;
  double expectedAPR = 0.0;
  int expectedTransfers = 0;
  String completionDate = "";

  // List to hold use of funds rows
  List<Map<String, String>> useOfFundsRows = [];
  Map<String, dynamic>? config;

  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    loadConfigurations();
  }

  // Fetch configurations from the API
  void loadConfigurations() async {
    try {
      ApiService apiService = ApiService();
      Map<String, dynamic> fetchedConfig = await apiService.fetchConfigurations();
      setState(() {
        config = fetchedConfig;
        dropdownValue = config?['use_of_funds']['value'].split('*')[0] ?? "";
        repaymentFrequency = config?['revenue_shared_frequency']['value'].split('*')[0] ?? "";
        repaymentDelay = config?['desired_repayment_delay']['value'].split('*')[0] ?? "";
        loanController.text = config?['funding_amount_min']['value'] ?? "25000";
        isLoading = false;
      });
    } catch (e) {
      print('API Call Error: $e');
      setState(() {
        hasError = true;
        isLoading = false;
      });
    }
  }

  // Add a new row to the use of funds table
  void addUseOfFundsRow() {
  final cleanAmount = amountController.text.replaceAll('\$', '').trim();
  final parsedAmount = double.tryParse(cleanAmount);
  if (dropdownValue.isNotEmpty &&
      descriptionController.text.isNotEmpty &&
      parsedAmount != null) {
    setState(() {
      useOfFundsRows.add({
        'type': dropdownValue,
        'description': descriptionController.text,
        'amount': '\$${parsedAmount.toStringAsFixed(2)}',
      });
      descriptionController.clear();
      amountController.clear();
    });
  } else {
    // Show error message if inputs are invalid
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please enter a valid amount')),
    );
  }
 }

  // Delete a row from the use of funds table
  void deleteUseOfFundsRow(int index) {
    setState(() {
      useOfFundsRows.removeAt(index);
    });
  }

  // Calculate the expected completion date based on repayment frequency and delay
    String calculateCompletionDate(double expectedTransfers, int repaymentDelay, String frequency) {
    DateTime now = DateTime.now();
    DateTime completionDate = now;

    if (frequency.toLowerCase() == 'weekly') {
        completionDate = completionDate.add(Duration(days: expectedTransfers.toInt() * DateTime.daysPerWeek)); 
    } else if (frequency.toLowerCase() == 'monthly') {
        completionDate = DateTime(
            completionDate.year,
            completionDate.month + expectedTransfers.toInt(),
            completionDate.day
        );
      }

      // Add repayment delay
      completionDate = completionDate.add(Duration(days: repaymentDelay));

      return DateFormat('MMMM dd, yyyy').format(completionDate);
    }

  // Calculate results based on user inputs and configurations
  void calculateResults() {
    setState(() {
        double annualRevenue = double.tryParse(revenueController.text) ?? 0.0;
        double loanAmount = double.tryParse(loanController.text) ?? 0.0;
        double revenue_percentageMin = double.tryParse(config?['revenue_percentage_min']['value'] ?? '0.0') ?? 0.0;
        double revenue_percentageMax = double.tryParse(config?['revenue_percentage_max']['value'] ?? '0.0') ?? 0.0;

        // Return if inputs are invalid
        if (annualRevenue <= 0.0 || loanAmount <= 0.0) {
            expectedTransfers = 0;
            return;
        }

        // Calculate revenue share percentage and fees
        revenueSharePercentage = evaluateFormula(
            config?['revenue_percentage']['value'] ?? "",
            annualRevenue,
            loanAmount,
        );
        feePercentage = double.tryParse(config?['desired_fee_percentage']['value'] ?? "0.0") ?? 0.0;
        feeAmount = loanAmount * feePercentage; 
        totalRevenueShare = loanAmount + feeAmount;
        revenueSharePercentage = revenueSharePercentage.clamp(revenue_percentageMin, revenue_percentageMax);
        double revenueShareAsFraction = revenueSharePercentage / 100;

        // Calculate expected transfers
        double divisor = (annualRevenue * (revenueSharePercentage / 100)).toDouble();
        if (divisor > 0) {
            if (repaymentFrequency.toLowerCase() == "weekly") {
                expectedTransfers = ((totalRevenueShare * 52) / divisor).ceil();
            } else if (repaymentFrequency.toLowerCase() == "monthly") {
                expectedTransfers = ((totalRevenueShare * 12) / divisor).ceil();
            } else {
                expectedTransfers = 0;
            }     
            } else {
            expectedTransfers = 0;
        }

        // Calculate completion date
        int repaymentDelayDays = int.tryParse(repaymentDelay.split(' ')[0]) ?? 0;
        completionDate = calculateCompletionDate(
            expectedTransfers.toDouble(),
            repaymentDelayDays,
            repaymentFrequency,
        );

        // **Calculate Expected APR**
        DateTime today = DateTime.now();
        DateTime expectedCompletionDate = DateFormat('MMMM dd, yyyy').parse(completionDate);
        int daysToCompletion = expectedCompletionDate.difference(today).inDays;

        if (daysToCompletion > 0) {
            expectedAPR = ((feePercentage / daysToCompletion) * 365 * 100);
        } else {
            expectedAPR = 0.0; // Avoid division by zero
        }
    });
  }
  
    /*
   * The `evaluateFormula` method is responsible for dynamically calculating a value
   * based on a formula provided in the API response. It replaces placeholders 
   * with actual values, processes the formula using a mathematical parser, 
   * and returns the computed result.
   *
   * Step 1: The function receives three parameters: 
   *         - `formula`: A string containing a mathematical formula (e.g., "funding_amount / revenue_amount")
   *         - `revenue`: The user's business revenue input.
   *         - `loanAmount`: The user's loan amount input.
   *
   * Step 2: The function replaces the placeholder values in the formula string 
   *         with actual numbers. 
   *         - "revenue_amount" is replaced with the value of `revenue.toString()`
   *         - "funding_amount" is replaced with the value of `loanAmount.toString()`
   *         
   * Step 3: The function ensures that division ("/") and multiplication ("*") 
   *         have proper spacing. This prevents potential parsing issues where 
   *         operators might be incorrectly interpreted.
   *
   * Step 4: It initializes a `Parser` object and uses it to parse the modified 
   *         formula string into an `Expression`. 
   *         
   * Step 5: A `ContextModel` is created. This is required by the Math Expressions library 
   *         to provide a scope for variable evaluation (although we do not use variables explicitly).
   *
   * Step 6: The `evaluate()` method is called on the parsed expression with 
   *         `EvaluationType.REAL`, which means it evaluates the expression as a real number.
   *
   * Step 7: The final computed result is multiplied by 100 to convert it into a percentage 
   *         (if required by the business logic).
   *
   * Step 8: If an error occurs during parsing or evaluation, the function catches the error, 
   *         prints an error message for debugging, and returns `0.0` as a fallback.
   */

  double evaluateFormula(String formula, double revenue, double loanAmount) {
    try {
        formula = formula.replaceAll("revenue_amount", revenue.toString());
        formula = formula.replaceAll("funding_amount", loanAmount.toString());
        formula = formula.replaceAll("/", " / ");
        formula = formula.replaceAll("*", " * ");

        Parser parser = Parser();
        Expression exp = parser.parse(formula);
        ContextModel cm = ContextModel();
        double result = exp.evaluate(EvaluationType.REAL, cm);
        return result * 100; 
        } catch (e) {
        print("Error evaluating formula: $e");
        return 0.0;
    }
  }

    // Build a result row for the results section
    Widget buildResultRow(String label, dynamic value) {
        return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Text(
                    label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                    ),
                ),
                Text(
                    value.toString(),
                    style: TextStyle(
                        fontSize: 16,
                    ),
                ),
            ],
        );
    }

  @override
  Widget build(BuildContext context) {
    // Show loading spinner while configurations are being fetched
    if (isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show error message if configurations failed to load
    if (hasError || config == null) {
      return Scaffold(body: Center(child: Text('Failed to load data')));
    }

    // Calculate slider and input limits
    final fundingAmountMin = double.tryParse(config?['funding_amount_min']['value'] ?? '25000') ?? 25000;
    final fundingAmountMax = double.tryParse(config?['funding_amount_max']['value'] ?? '75000') ?? 75000;
    final businessRevenue = double.tryParse(revenueController.text) ?? 0.0;
    final dynamicMaxValue = ((businessRevenue / 3).clamp(fundingAmountMin, fundingAmountMax));
    final sliderValue = (double.tryParse(loanController.text) ?? fundingAmountMin).clamp(fundingAmountMin, dynamicMaxValue);

    // Configuration values for dropdowns
    final repaymentDelays = (config?['desired_repayment_delay']['value'] ?? '').split('*');
    final useOfFundsOptions = (config?['use_of_funds']['value'] ?? '').split('*');
    final useOfFundsLabel = config?['use_of_funds']['label'] ?? 'Use of Funds';

    return Scaffold(
       body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Section: Financing Options
            Expanded(
              child: Container(
              color: Colors.white,
              height:double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 25.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text("Financing Options", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), 
                            const SizedBox(height: 16),
                            Row(
                                children: [
                                    Text(
                                        config?['revenue_amount']['label'] ?? '',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const Text(
                                        ' *',
                                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                    ),
                                ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                                controller: revenueController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: config?['revenue_amount']['placeholder'] ?? '',
                                ),
                                onChanged: (value) {
                                    setState(() {
                                    if (double.tryParse(value) == null && value.isNotEmpty) {
                                        // Show existing Snackbar if input is invalid
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Please enter a valid amount')),
                                        );
                                        revenueController.clear();
                                        return;
                                    }

                                    final newRevenue = double.tryParse(value) ?? 0.0;
                                    if (newRevenue > 0) {
                                        final newMax = newRevenue / 3;
                                        if (sliderValue > newMax) {
                                            loanController.text = fundingAmountMin.toStringAsFixed(2);
                                        }
                                    }
                                    calculateResults();
                                    });
                                },
                            ),
                        ],
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config?['funding_amount']['label'] ?? 'What is your desired loan amount?',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('\$${fundingAmountMin.toStringAsFixed(0)}'),
                                Text(''),
                              ],
                            ),
                            Positioned(
                              right: 120,
                              child: Text('\$${dynamicMaxValue.toStringAsFixed(0)}'),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Slider(
                                value: sliderValue,
                                min: fundingAmountMin,
                                max: dynamicMaxValue,
                                divisions: 100,
                                label: '\$${sliderValue.toStringAsFixed(0)}',
                                onChanged: (value) {
                                  setState(() {
                                    loanController.text = value.toStringAsFixed(2);
                                    calculateResults();
                                  });
                                },
                              ),
                            ),                           
                            const SizedBox(width: 10),
                            Container(
                              width: 100,
                              child: TextField(
                                controller: loanController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: '\$${fundingAmountMin.toStringAsFixed(0)}',
                                ),
                                onSubmitted: (value) {
                                  final newValue = double.tryParse(value) ?? fundingAmountMin;
                                  if (newValue >= fundingAmountMin && newValue <= dynamicMaxValue) {
                                    setState(() {
                                      loanController.text = newValue.toStringAsFixed(2);
                                      calculateResults();
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                            Text(
                                '${config?['revenue_percentage']['label'] ?? 'Revenue share percentage:'} ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              (revenueController.text.isEmpty || double.tryParse(revenueController.text) == null || double.tryParse(revenueController.text) == 0.0)
                              ? '-'  // Show "-" if revenue is not entered or 0
                              : '${revenueSharePercentage.toStringAsFixed(2)}%',  // Show calculated percentage if valid
                              style: TextStyle(fontSize: 16, color: Colors.deepPurple),
                            ),
                        ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                            Text(
                                '${config?['revenue_shared_frequency']['label'] ?? 'Repayment Frequency:'} ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Row(
                                children: (config?['revenue_shared_frequency']['value'] ?? '')
                                .split('*')
                                .map<Widget>(
                                    (option) => Row(
                                        children: [
                                            Radio(
                                                value: option,
                                                groupValue: repaymentFrequency,
                                                onChanged: (value) {
                                                    setState(() {
                                                        repaymentFrequency = value.toString();
                                                        calculateResults();
                                                    });
                                                },
                                            ),
                                            Text(option),
                                        ],
                                    ),
                                )
                                .toList(),
                            ),
                        ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                            Text(
                                config?['desired_repayment_delay']['label'] ?? 'Repayment Delay:',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 16),
                            Container(
                                width: 150,
                                child: buildDropdown(
                                    (config?['desired_repayment_delay']['value'] ?? '').split('*'),
                                    repaymentDelay,
                                    (value) {
                                        setState(() {
                                            repaymentDelay = value!;
                                             calculateResults();
                                        });
                                    },
                                ),
                            ),
                        ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                        useOfFundsLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                        children: [
                            Container(
                                width: 150,
                                child: buildDropdown(
                                    useOfFundsOptions,
                                    dropdownValue,
                                    (value) {
                                        setState(() {
                                        dropdownValue = value!;
                                        });
                                    },
                                ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                                child: TextField(
                                    controller: descriptionController,
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'Description',
                                    ),
                                ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                                width: 100,
                                child: TextField(
                                    controller: amountController,
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'Amount',
                                    ),
                                    keyboardType: TextInputType.number,
                                ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.deepPurple,),
                                onPressed: addUseOfFundsRow,
                            ),
                        ],
                    ),
                    const SizedBox(height: 20),
                    ListView.builder(
                        shrinkWrap: true,
                        itemCount: useOfFundsRows.length,
                        itemBuilder: (context, index) {
                            final row = useOfFundsRows[index];
                            return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Row(
                                    children: [
                                        Text(row['type'] ?? ''),
                                        const SizedBox(width: 20),
                                        Expanded(child: Text(row['description'] ?? '')),
                                        const SizedBox(width: 20),
                                        Text(row['amount'] ?? ''),
                                        const SizedBox(width: 10),
                                        IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.deepPurple,),
                                            onPressed: () {
                                                deleteUseOfFundsRow(index);
                                            },
                                        ),
                                    ],
                                ),
                            );
                        },
                    ),
                  ],
                ),
              ),
            ),
            ),
            
            // Right Section: Results
            const SizedBox(width:20),
            Expanded(
                child: Container(
                    color: Colors.white,
                    child: Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                    'Results',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                    ),
                                ),
                                const SizedBox(height: 24),
                                buildResultRow('Annual Business Revenue', '\$${revenueController.text}'),
                                const SizedBox(height: 16),
                                buildResultRow('Funding Amount', '\$${loanController.text}'),
                                const SizedBox(height: 16),
                                buildResultRow(
                                    'Fees',
                                    '(${(feePercentage * 100).toStringAsFixed(0)}%) \$${feeAmount.toStringAsFixed(2)}',
                                ),
                                const SizedBox(height: 16),
                                buildResultRow('Expected APR', '${expectedAPR.toStringAsFixed(2)}%'), // **New Field**
                                const SizedBox(height: 16),
                                const Divider(thickness: 1.0, color: Colors.grey),
                                const SizedBox(height: 16),
                                buildResultRow(
                                    'Total Revenue Share',
                                    '\$${totalRevenueShare.toStringAsFixed(2)}',
                                ),
                                const SizedBox(height: 16),
                                buildResultRow('Expected Transfers', expectedTransfers.toString()),
                                const SizedBox(height: 16),
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                        Text(
                                            'Expected completion date',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                            ),
                                        ),
                                        Text(
                                            completionDate,
                                            style: TextStyle(
                                                color: Colors.deepPurple,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                            ),
                                        ),
                                    ],
                                ),
                            ],
                        ),
                    ),
                ),
            ),
          ],
        ),
      ),
    );
  }
}
