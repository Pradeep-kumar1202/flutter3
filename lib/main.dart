import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_hyperswitch/flutter_hyperswitch.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final String _endpoint =
      Platform.isAndroid ? "http://10.0.2.2:5252" : "http://localhost:5252";
  final _hyper = FlutterHyperswitch();

  Session? _sessionId;
  SavedSession? _savedSessionId;

  String _statusText = '';
  String _defaultPaymentMethodText = '';
  String _confirmStatusText = '';

  bool _isInitialized = false;
  bool _showChangeButton = false;
  int _confirmState = 0;

  @override
  void initState() {
    super.initState();
    _initPlatformState();
  }

  Future<void> _initPlatformState() async {
    final response =
        await http.get(Uri.parse("$_endpoint/create-payment-intent"));
    if (response.statusCode == 200) {
      final responseBody =
          jsonDecode(response.body) as Map<String, dynamic>; //Decoding the Json
      _hyper.init(HyperConfig(publishableKey: responseBody['publishableKey']));
      try {
        _sessionId = await _hyper.initPaymentSession(PaymentMethodParams(
            clientSecret: responseBody['clientSecret'],
            configuration: Configuration(
                displayDefaultSavedPaymentIcon: false,
                paymentSheetHeaderLabel: "Payment methods",
                savedPaymentSheetHeaderLabel: "Select payment method",
                primaryButtonLabel: "Purchase (\$2.00)",
                netceteraSDKApiKey: "1300d8f6-69b1-4b65-b0ae-f8e36ccc0a92",
                appearance: Appearance(
                    googlePay: GPayParams(
                      buttonType: GPayButtonType.donate,
                      buttonStyle: GPayButtonStyle(
                        light: GPayButtonStyleType.light,
                        dark: GPayButtonStyleType.light,
                      ),
                    ),
                    applePay: ApplePayParams(
                      buttonType: ApplePayButtonType.donate,
                      buttonStyle: ApplePayButtonStyle(
                        light: ApplePayButtonStyleType.whiteOutline,
                        dark: ApplePayButtonStyleType.whiteOutline,
                      ),
                    ),
                    font: Font(family: "Montserrat"),
                    colors: DynamicColors(
                        dark: ColorsObject(
                            primary: "#8DBD00", background: "#F5F8F9"),
                        light: ColorsObject(
                            primary: "#8DBD00", background: "#F5F8F9")),
                    primaryButton: PrimaryButton(
                        colors: DynamicColors(
                            dark: ColorsObject(primaryText: "yellow"),
                            light: ColorsObject(primaryText: "yellow")),
                        shapes: Shapes(borderRadius: 32.0))))));
      } catch (ex) {
        print((ex as HyperswitchException).message);
      }
      setState(() {
        _isInitialized = _sessionId != null;
        _statusText =
            _isInitialized ? _statusText : "initPaymentSession failed";
      });
    } else {
      setState(() {
        _statusText = "API Call Failed";
      });
    }
  }

  Future<void> _initializeHeadless() async {
    if (_sessionId == null) {
      setState(() {
        _defaultPaymentMethodText = "SessionId is empty";
        _statusText = "";
      });
      return;
    }
    try {
      _savedSessionId =
          await _hyper.getCustomerSavedPaymentMethods(_sessionId!);
      final paymentMethod = await _hyper
          .getCustomerLastUsedPaymentMethodData(_savedSessionId!); // Later
      if (paymentMethod is PaymentMethod) {
        if (paymentMethod is Card) {
          final card = paymentMethod;
          _setDefaultPaymentMethodText(
              "${card.nickName}  ${card.cardNumber}  ${card.expiryDate}", true);
          _showChangeButton = true;
        } else if (paymentMethod is Wallet) {
          final wallet = paymentMethod;
          _setDefaultPaymentMethodText(wallet.walletType.name, true);
        }
      } else if (paymentMethod is PaymentMethodError) {
        _setDefaultPaymentMethodText(paymentMethod.message, false);
      } else {
        _setDefaultPaymentMethodText(
            "getCustomerDefaultSavedPaymentMethodData failed", false);
      }
    } catch (error) {
      _handleError(error, 1);
    }
  }

  Future<void> _confirmPayment() async {
    // setState(() {
    //   _confirmState = 1;
    // });
    try {
      if (_savedSessionId != null) {
        final confirmWithCustomerDefaultPaymentMethodResponse =
            await _hyper.confirmWithLastUsedPaymentMethod(_savedSessionId!);
        final message = confirmWithCustomerDefaultPaymentMethodResponse.message;
        if (message != null) {
          _setConfirmStatusText(
              "${confirmWithCustomerDefaultPaymentMethodResponse.status.name}\n${message.name}");
        } else {
          _setConfirmStatusText(
              "${confirmWithCustomerDefaultPaymentMethodResponse.status.name}\n${confirmWithCustomerDefaultPaymentMethodResponse.error.message}");
        }
      } else {
        _setConfirmStatusText("SavedSession is empty");
      }
    } catch (error) {
      _handleError(error, 2);
    } finally {
      setState(() {
        _showChangeButton = false;
        _defaultPaymentMethodText = '';
        _confirmState = 0;
        _initPlatformState();
      });
    }
  }

  Future<void> _presentPaymentSheet(bool isHeadless) async {
    setState(() {
      _isInitialized = false;
    });
    if (_sessionId == null) {
      _setStatusText("SessionId is empty");
      return;
    }
    try {
      final presentPaymentSheetResponse =
          await _hyper.presentPaymentSheet(_sessionId!);
      if (isHeadless) {
        _setConfirmStatusText(_buildMessage(
            presentPaymentSheetResponse.status.name,
            presentPaymentSheetResponse.message,
            presentPaymentSheetResponse.error.message));
      } else {
        _setStatusText(_buildMessage(
            presentPaymentSheetResponse.status.name,
            presentPaymentSheetResponse.message,
            presentPaymentSheetResponse.error.message));
      }
      Status status = presentPaymentSheetResponse.status;
      if (status != Status.cancelled) {
        Fluttertoast.showToast(
            msg: status == Status.completed ? "Success" : "Failed",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor:
                status == Status.completed ? Colors.green : Colors.red,
            textColor: Colors.white,
            fontSize: 16.0);
        setState(() {
          _showChangeButton = false;
          _defaultPaymentMethodText = '';
          _confirmState = 0;
          _initPlatformState();
        });
      } else if (status == Status.cancelled) {
        Fluttertoast.showToast(
            msg: "User Cancelled",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.orange,
            textColor: Colors.white,
            fontSize: 16.0);
      }
      setState(() {
        _isInitialized = true;
      });
    } catch (error) {
      _handleError(error, 0);
    }
  }

  String _buildMessage(String status, Result? message, String error) {
    if (message != null) {
      return "$status\n${message.name}";
    } else {
      return "$status\n$error";
    }
  }

  void _handleError(dynamic error, int flow) {
    final errorMessage =
        error is HyperswitchException ? error.message : error.toString();
    if (flow == 0) {
      _setStatusText(errorMessage);
    } else if (flow == 1) {
      _setDefaultPaymentMethodText(errorMessage, false);
    } else if (flow == 2) {
      _setConfirmStatusText(errorMessage);
    }
  }

  void _setStatusText(String text) {
    setState(() {
      _statusText = text;
    });
  }

  void _setDefaultPaymentMethodText(String text, bool show) {
    setState(() {
      _defaultPaymentMethodText = text;
      _confirmStatusText = '';
      if (show) {
        _confirmState = 2;
      }
    });
  }

  void _setConfirmStatusText(String text) {
    setState(() {
      _confirmStatusText = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'montserrat'),
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Plugin example app',
            style: TextStyle(color: Colors.white),
          ),
          elevation: 10,
          backgroundColor: Colors.deepPurple,
        ),
        body: getBody(),
      ),
    );
  }

  Widget getBody() {
    return Container(
      width: MediaQuery.of(context).size.width,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: MediaQuery.of(context).size.width * 0.3),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color.fromARGB(255, 0, 0, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width,
              alignment: Alignment.center,
              child: const Text(
                'Initialize Headless SDK',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.amber,
                ),
              ),
            ),
          ),
          const SizedBox(height: 60),
          ElevatedButton(
            onPressed: _isInitialized
                ? () {
                    _presentPaymentSheet(false);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(15),
              backgroundColor: const Color.fromARGB(255, 5, 5, 5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width,
              alignment: Alignment.center,
              child: Text(
                _isInitialized ? "Open Payment Sheet" : "Processing ...",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.amber,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
