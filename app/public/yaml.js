window.addEventListener("load", function() {
	function forEach(collection, operation) {
		Array.prototype.forEach.call(collection, operation);
	}

	function find(collection, condition) {
		return Array.prototype.find.call(collection, condition);
	}

	function nameRegexp(ol) {
		return new RegExp(ol.dataset.key.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&") + "\\[\\d+\\]");
	}

	function buildName(string, ol, number) {
		return string.replace(nameRegexp(ol), ol.dataset.key + "[" + number + "]");
	}

	function enableDisableMoveButtons(ol, li, number) {
		find(li.firstChild.children, function(el) { return el.className === "move-up"; }).disabled = number < 1;
		find(li.firstChild.children, function(el) { return el.className === "move-down"; }).disabled = number >= ol.children.length - 1;
	}

	function notInNestedList(el, targetParent) {
		// We should only hydrate "direct" children that are not in a
		// descendant ol[data-key]
		var traverseParents = el.parentElement;
		while(traverseParents && traverseParents.nodeName !== "OL" && !traverseParents.dataset.key) {
			traverseParents = traverseParents.parentElement;
		}

		return traverseParents === targetParent;
	}

	function hydrateLi(li) {
		var fieldset = li.firstChild;

		function findOrCreateButton(className, label) {
			var button = find(fieldset.children, function(el) { return el.className === className; });

			if(!button) {
				button = document.createElement("button");
				fieldset.insertBefore(button, fieldset.firstChild);

				button.type = "button";
				button.className = className;
				button.textContent = label;
			}

			return button;
		}

		findOrCreateButton("move-up", "▲").addEventListener("click", function() {
			li.parentNode.insertBefore(li, li.previousElementSibling);
			renumber(li.parentNode, li);
			renumber(li.parentNode, li.nextElementSibling);
		});

		findOrCreateButton("move-down", "▼").addEventListener("click", function() {
			li.parentNode.insertBefore(li.nextElementSibling, li);
			renumber(li.parentNode, li);
			renumber(li.parentNode, li.previousElementSibling);
		});

		findOrCreateButton("clone", "Clone").addEventListener("click", function() {
			var item = li.cloneNode(true);
			renameAppendHydrate(li.parentElement, item);
		});

		enableDisableMoveButtons(li.parentNode, li, Array.prototype.indexOf.call(li.parentNode.children, li));

		forEach(li.querySelectorAll("input[type=file]"), function(fileInput) {
			if(notInNestedList(fileInput, li.parentElement)) {
				fileBrowser(fileInput);
			}
		});

		forEach(li.querySelectorAll("fieldset"), function(fieldset) {
			if(fieldset.parentElement !== li && notInNestedList(fieldset, li.parentElement)) {
				hydrateFieldset(fieldset);
			}
		});
	}

	function renumber(ol, li) {
		var number = Array.prototype.indexOf.call(ol.children, li);

		if(number === -1) {
			number = ol.children.length;
		}

		forEach(li.querySelectorAll('input, textarea, select'), function(el) {
			el.name = buildName(el.name, ol, number);
		});

		forEach(li.querySelectorAll('ol[data-key]'), function(el) {
			el.dataset.key = buildName(el.dataset.key, ol, number);
		});

		enableDisableMoveButtons(ol, li, number);
	}

	function renameAppendHydrate(ol, item, resetValue) {
		renumber(ol, item);

		if(resetValue) {
			forEach(item.querySelectorAll('input, textarea, select'), function(el) {
				el.value = '';
			});

			forEach(item.querySelectorAll("input[type='file']"), function(input) {
				var image = input.previousElementSibling.previousElementSibling.nodeName === "IMG" &&
										input.previousElementSibling.previousElementSibling;

				if(image) {
					image.parentNode.removeChild(image);
				}
			});
		}

		forEach(item.querySelectorAll('ol[data-key]'), function(el) {
			hydrate(el);
		});

		ol.appendChild(item);
		hydrateLi(item);
		renumber(ol, item.previousElementSibling);

		if(item.getBoundingClientRect().bottom > window.innerHeight) {
			item.scrollIntoView(false);
		}
	}

	function hydrate(ol) {
		var button = ol.parentElement.lastElementChild;
		button.addEventListener("click", function() {
			var item = ol.lastElementChild.cloneNode(true);
			forEach(item.querySelectorAll('ol > li:not(:first-of-type)'), function(el) {
				el.parentNode.removeChild(el);
			});

			renameAppendHydrate(ol, item, true)
		});

		forEach(ol.children, function(li, i) {
			hydrateLi(li);
		});
	}

	function toggleFieldset(fieldset) {
		forEach(fieldset.children, function(el) {
			if(el.nodeName !== "LEGEND") {
				el.style.display = el.style.display === "none" ? "block" : "none";
			}
		});
	}

	function hydrateFieldset(fieldset) {
		forEach(fieldset.children, function(el) {
			if(el.nodeName === "LEGEND") {
				el.addEventListener("click", function() {
					toggleFieldset(fieldset);
				});
			} else {
				el.style.display = "none";
			}
		});
	}

	forEach(document.querySelectorAll("form ol[data-key] > li:last-child"), function(li) {
		var ol = li.parentElement;
		var button = document.createElement("button");
		button.type = "button";
		button.textContent = "New Item";
		ol.parentElement.appendChild(button);
		hydrate(ol);
	});

	forEach(document.querySelectorAll(".yml > label > input[type=file]"), fileBrowser);
	forEach(document.querySelectorAll(".yml fieldset"), function(fieldset) {
		if(notInNestedList(fieldset, null)) {
			hydrateFieldset(fieldset);
		}
	});

	var hidden = document.querySelectorAll("form .hidden");
	forEach(hidden, function(el) { el.style.display = 'none'; });
});
