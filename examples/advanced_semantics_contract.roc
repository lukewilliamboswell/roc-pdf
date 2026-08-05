app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Semantics

pdf20 = Semantics.NamespaceId.from_index(0)

mathml = Semantics.NamespaceId.from_index(1)

## Role mappings retain source and target namespace identity independently.
expect {
	mapping : Semantics.RoleMapping
	mapping = {
		from: { local_name: "equation", namespace: mathml },
		to: { local_name: "Formula", namespace: pdf20 },
	}

	mapping.from.namespace.index() == 1 and mapping.to.namespace.index() == 0
}

## Structure attributes carry typed names, owners, values, and applicability.
expect {
	attribute : Semantics.StructureAttribute
	attribute = {
		applicability: ExactRoles(Semantics.Range.from_start_and_length(0, 2)),
		name: Standard("Scope"),
		owner: Table,
		value: Name("Column"),
	}

	attribute.owner == Table and match attribute.applicability {
		ExactRoles(roles) => roles.start() == 0 and roles.length() == 2
		_ => False
	}
}

## Table header relationships use IDTree identities rather than adding parents.
expect {
	relationship : Semantics.Relationship
	relationship = HeaderFor({
		cell: Semantics.ElementId.from_index(4),
		header: Semantics.ElementId.from_index(2),
	})

	match relationship {
		HeaderFor({ cell, header }) => cell.index() == 4 and header.index() == 2
		_ => False
	}
}

## Parsed MathML carries bounded validation work and no unchecked markup bytes.
expect {
	subtree : Semantics.MathMlSubtree
	subtree = {
		id: Semantics.MathMlSubtreeId.from_index(0),
		namespace: mathml,
		nodes: Semantics.Range.from_start_and_length(7, 3),
		origin: ValidatedParse({
			source: Semantics.NonTextSourceId.from_index(0),
			work: { attribute_visits: 2, node_visits: 3, utf8_bytes: 48 },
		}),
		root: Semantics.NodeId.from_index(7),
	}

	subtree.root.index() == 7 and subtree.nodes.length() == 3
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
