package de.unibremen.informatik.Fact;

import uk.ac.manchester.cs.factplusplus.owlapi.*;
import org.semanticweb.reasonerfactory.factpp.*;

import org.semanticweb.owl.inference.*;

import org.semanticweb.owl.apibinding.OWLManager;
import org.semanticweb.owl.io.OWLXMLOntologyFormat;
import org.semanticweb.owl.model.*;
import java.net.URI;
import java.util.*;

class Fact
{

    public static void main (String[] args)
    {
	if (args.length < 1) 
	    {
		System.out.println("owl_fact <Ontology>");
		System.exit(1);
	    }

	try
	    {
		OWLOntologyManager manager = 
		    OWLManager.createOWLOntologyManager();
		OWLReasonerFactory fac = new FaCTPlusPlusReasonerFactory();
		OWLReasoner reasoner = fac.createReasoner(manager);
		URI physicalURI = URI.create(args[0]);
		OWLOntology ontology = 
		    manager.loadOntologyFromPhysicalURI(physicalURI);
		TreeSet ontos = new TreeSet();
		ontos.add(ontology);
		reasoner.loadOntologies(ontos);
		Boolean cons = reasoner.isConsistent(ontology);
		if (cons)
		    {
			System.out.println("consistent");
			System.exit(10);
		    }
		else
		    {
			System.out.println("inconsistent");
			System.exit(20);
		    }
	    }
	catch (OWLOntologyCreationException e)
	    {
		System.out.println("The ontology could not be created: " + 
				   e.getMessage());
		System.exit(1);
	    }
	catch (Exception e)
	    {
		System.out.println("Exception: " + 
				   e.getMessage());
		System.exit(1);
	    }
    }

}
