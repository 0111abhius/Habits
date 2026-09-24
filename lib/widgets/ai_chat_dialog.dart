import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AIChatDialog extends StatefulWidget {
  final String title;
  final String initialPrompt;
  final ChatSession chatSession;

  const AIChatDialog({
    super.key,
    required this.title,
    required this.initialPrompt,
    required this.chatSession,
  });

  @override
  State<AIChatDialog> createState() => _AIChatDialogState();
}

class _AIChatDialogState extends State<AIChatDialog> {
  final List<Content> _history = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    // Send initial prompt
    await _sendMessage(widget.initialPrompt, isUser: false); // Treat as system/hidden start
  }

  Future<void> _sendMessage(String text, {required bool isUser}) async {
    if (isUser) {
      setState(() {
        _history.add(Content.text(text));
        _loading = true;
      });
      _scrollToBottom();
      
      try {
        final response = await widget.chatSession.sendMessage(Content.text(text));
        final responseText = response.text ?? 'No response';
        if (mounted) {
          setState(() {
            _history.add(Content.model([TextPart(responseText)]));
            _loading = false;
          });
          _scrollToBottom();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _history.add(Content.model([TextPart('Error: $e')]));
            _loading = false;
          });
          _scrollToBottom();
        }
      }
    } else {
      // Initial System/User prompt logic
      // We actually want to send it as a message to get the first response.
      // But we might want to hide the prompt itself from the UI if it's the "hidden" analysis prompt.
      // For now, let's just trigger it.
      
      // If it's the very first call, we can just use sendMessage.
      try {
        final response = await widget.chatSession.sendMessage(Content.text(text));
        final responseText = response.text ?? '';
        if (mounted) {
          setState(() {
            // We don't show the initial big prompt in history, just the result
            _history.add(Content.model([TextPart(responseText)]));
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
             _history.add(Content.model([TextPart('Error starting chat: $e')]));
             _loading = false;
          });
        }
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _history.length,
                itemBuilder: (ctx, i) {
                  final msg = _history[i];
                  final isUser = msg.role == 'user';
                  final text = msg.parts.whereType<TextPart>().map((e) => e.text).join();
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(maxWidth: 600), // constrain width on wide screens
                      child: isUser 
                        ? Text(text) 
                        : MarkdownBody(data: text),
                    ),
                  );
                },
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ask a follow-up...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (val) {
                       if (val.trim().isNotEmpty && !_loading) {
                         _sendMessage(val.trim(), isUser: true);
                         _controller.clear();
                       }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _loading ? null : () {
                    final val = _controller.text.trim();
                     if (val.isNotEmpty) {
                       _sendMessage(val, isUser: true);
                       _controller.clear();
                     }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
